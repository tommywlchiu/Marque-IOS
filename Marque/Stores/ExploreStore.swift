import Foundation
import FirebaseFirestore

struct PublicUserProfile: Codable {
    @DocumentID var uid: String?
    let username: String
    let displayName: String
    let bio: String
    let avatarURL: String
}

/// The two Top Cars lists in Explore.
enum TopCarsPeriod: String, CaseIterable, Identifiable {
    case thisWeek
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisWeek: return "This Week"
        case .allTime: return "All Time"
        }
    }

    /// Server-maintained count on publicCars this list is ordered by.
    /// weeklyLikeCount is recomputed hourly (recomputeWeeklyLikes), so "This
    /// Week" can lag real likes by up to an hour; likeCount updates within
    /// seconds of a like (onCarLikeWritten).
    var countField: String {
        switch self {
        case .thisWeek: return "weeklyLikeCount"
        case .allTime: return "likeCount"
        }
    }

    func count(of car: PublicCar) -> Int {
        switch self {
        case .thisWeek: return car.weeklyLikeCount
        case .allTime: return car.likeCount
        }
    }
}

@MainActor
class ExploreStore: ObservableObject {
    @Published var cars: [PublicCar] = []
    @Published var isLoading = false

    /// Top Cars, most-liked first, at most `topCarsLimit`. Only cars with at
    /// least one like in the period appear. NOT block-filtered: run the
    /// result through `BlockStore.filter(_:ownerUID: \.ownerUID)` like the
    /// main feed.
    @Published private(set) var topCarsThisWeek: [PublicCar] = []
    @Published private(set) var topCarsAllTime: [PublicCar] = []
    @Published private(set) var isLoadingTopCars = false
    /// Periods whose most recent `loadTopCars` failed (the previous list is
    /// kept). Lets the UI tell a failed load from a genuinely empty ranking.
    @Published private(set) var topCarsFailedPeriods: Set<TopCarsPeriod> = []

    static let topCarsLimit = 50

    /// Set when the feed listener fails (Firestore then terminates it), so
    /// the UI can show an error with Retry instead of loading forever.
    /// Cleared by the next successful snapshot or refresh.
    @Published private(set) var feedLoadFailed = false

    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    private var profileCache: [String: PublicUserProfile] = [:]

    func startListening() {
        guard listener == nil else { return }
        isLoading = true
        listener = db.collection("publicCars")
            .order(by: "updatedAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                guard let snapshot else {
                    // A listener that errors is already terminated; drop it
                    // so retryFeed() can start a fresh one.
                    print("[ExploreStore] Feed listener failed: \(error?.localizedDescription ?? "unknown")")
                    self.listener?.remove()
                    self.listener = nil
                    self.isLoading = false
                    self.feedLoadFailed = true
                    return
                }
                self.isLoading = false
                self.feedLoadFailed = false
                self.cars = snapshot.documents.compactMap { try? $0.data(as: PublicCar.self) }
            }
    }

    // Manual pull-to-refresh. The live listener in startListening() already
    // keeps `cars` current, so this isn't fixing staleness in the normal
    // case — it's a forced server round-trip (bypassing any local cache)
    // for the case the listener silently dropped (e.g. after a network
    // blip) and to give pull-to-refresh a real action instead of a fake
    // delay. Mirrors startListening()'s query and decode; the listener's
    // own next snapshot will reconcile `cars` again regardless.
    func refresh() async {
        guard let snapshot = try? await db.collection("publicCars")
            .order(by: "updatedAt", descending: true)
            .limit(to: 100)
            .getDocuments(source: .server)
        else { return }
        cars = snapshot.documents.compactMap { try? $0.data(as: PublicCar.self) }
        if feedLoadFailed { retryFeed() }
    }

    /// Restarts the feed after `feedLoadFailed`.
    func retryFeed() {
        listener?.remove()
        listener = nil
        feedLoadFailed = false
        startListening()
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        feedLoadFailed = false
        cars = []
        profileCache = [:]
        topCarsThisWeek = []
        topCarsAllTime = []
        topCarsFailedPeriods = []
    }

    // MARK: - Top Cars

    func topCars(_ period: TopCarsPeriod) -> [PublicCar] {
        switch period {
        case .thisWeek: return topCarsThisWeek
        case .allTime: return topCarsAllTime
        }
    }

    /// One-shot fetch of a Top Cars list (not a listener: the ranking changes
    /// slowly, and a live listener on 50 docs would re-bill on every like).
    /// Call on appear and on pull-to-refresh. Single-field range + order on
    /// the same field: served by Firestore's automatic index, no composite
    /// index needed. On failure the previous list is kept and `period` is
    /// added to `topCarsFailedPeriods`.
    func loadTopCars(_ period: TopCarsPeriod) async {
        isLoadingTopCars = true
        defer { isLoadingTopCars = false }
        let snapshot: QuerySnapshot
        do {
            snapshot = try await db.collection("publicCars")
                .whereField(period.countField, isGreaterThan: 0)
                .order(by: period.countField, descending: true)
                .limit(to: Self.topCarsLimit)
                .getDocuments()
        } catch {
            print("[ExploreStore] Top Cars (\(period.rawValue)) failed: \(error.localizedDescription)")
            topCarsFailedPeriods.insert(period)
            return
        }
        topCarsFailedPeriods.remove(period)
        let cars = snapshot.documents.compactMap { try? $0.data(as: PublicCar.self) }
        switch period {
        case .thisWeek: topCarsThisWeek = cars
        case .allTime: topCarsAllTime = cars
        }
    }

    func cars(for ownerUID: String) -> [PublicCar] {
        cars.filter { $0.ownerUID == ownerUID }
    }

    func results(matching query: String) -> [PublicCar] {
        guard !query.isEmpty else { return cars }
        let q = query.lowercased()
        return cars.filter {
            $0.make.lowercased().contains(q) ||
            $0.model.lowercased().contains(q) ||
            $0.year.contains(q) ||
            $0.ownerUsername.lowercased().contains(q)
        }
    }

    func fetchUserProfile(uid: String) async -> PublicUserProfile? {
        if let cached = profileCache[uid] { return cached }
        guard let doc = try? await db.collection("users").document(uid).getDocument(),
              let profile = try? doc.data(as: PublicUserProfile.self) else { return nil }
        profileCache[uid] = profile
        return profile
    }

    // FollowStore only tracks the current user's edges — for foreign profiles
    // we one-shot the target user's followers/following subcollections.
    func fetchFollowUIDs(uid: String) async -> (followers: Set<String>, following: Set<String>) {
        async let followers = fetchUIDs(subcollection: "followers", ownerUID: uid)
        async let following = fetchUIDs(subcollection: "following", ownerUID: uid)
        return (await followers, await following)
    }

    private func fetchUIDs(subcollection: String, ownerUID: String) async -> Set<String> {
        let snap = try? await db.collection("users").document(ownerUID).collection(subcollection).getDocuments()
        return Set(snap?.documents.map { $0.documentID } ?? [])
    }
}
