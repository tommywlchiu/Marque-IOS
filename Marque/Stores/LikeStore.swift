import Foundation
import FirebaseFirestore

/// Likes on public cars: `publicCars/{carId}/likes/{uid}` = `{ uid, createdAt }`.
///
/// Holds the signed-in user's own liked set through one collection-group
/// listener (`collectionGroup("likes").whereField("uid", ==, me)`), so
/// `isLiked` is a local set lookup for any car on screen. Toggling is
/// optimistic with rollback. The public `likeCount` is maintained server-side
/// (onCarLikeWritten) and lags a toggle by a second or two, so
/// `displayedLikeCount(for:)` bridges that gap.
///
/// Rules (firestore.rules): you can't like your own car, and a like is denied
/// when either you or the owner has blocked the other. `canLike` covers the
/// first; filter blocked owners out of the UI with BlockStore for the second.
@MainActor
final class LikeStore: ObservableObject {
    /// carIds (`PublicCar.carId`) the current user has liked.
    @Published private(set) var likedCarIDs: Set<String> = []
    /// Set when a like/unlike is rejected (e.g. blocked, car no longer
    /// public, offline write rejected). Cleared by `clearError()`.
    @Published private(set) var lastError: String?

    /// Max likes loaded into `likedCarIDs`. A user with more likes than this
    /// may see an old like as not-liked; tapping it again is then a no-op create
    /// that the rules deny as an update, and the heart rolls back.
    static let listenerLimit = 1000

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var currentUID: String?
    /// Toggles in flight: carId -> liked state we're writing. The listener's
    /// snapshots don't override these until the write settles.
    private var pending: [String: Bool] = [:]
    /// likeCount the UI saw when the user toggled, and the delta applied.
    private var countBaseline: [String: (seen: Int, delta: Int)] = [:]

    func startListening(uid: String) {
        guard uid != currentUID else { return }
        stopListening()
        currentUID = uid
        listener = db.collectionGroup("likes")
            .whereField("uid", isEqualTo: uid)
            .limit(to: Self.listenerLimit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.currentUID == uid else { return }
                if let error {
                    print("[LikeStore] Listener error: \(error.localizedDescription)")
                    return
                }
                guard let snapshot else { return }
                var ids = Set(snapshot.documents.compactMap { $0.reference.parent.parent?.documentID })
                for (carId, liked) in self.pending {
                    if liked { ids.insert(carId) } else { ids.remove(carId) }
                }
                self.likedCarIDs = ids
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        currentUID = nil
        likedCarIDs = []
        pending = [:]
        countBaseline = [:]
        lastError = nil
    }

    func isLiked(_ carId: String) -> Bool {
        likedCarIDs.contains(carId)
    }

    /// False for the user's own car (the rules deny self-likes). Hide or
    /// disable the heart then.
    func canLike(_ car: PublicCar) -> Bool {
        guard let currentUID else { return false }
        return car.ownerUID != currentUID
    }

    /// `car.likeCount` adjusted for this user's toggle until the server
    /// count catches up (i.e. until `car.likeCount` differs from the value seen
    /// at toggle time). Never negative.
    func displayedLikeCount(for car: PublicCar) -> Int {
        guard let base = countBaseline[car.carId], base.seen == car.likeCount else {
            return car.likeCount
        }
        return max(0, base.seen + base.delta)
    }

    /// Likes or unlikes `carId`. Optimistic: `isLiked` flips immediately and
    /// rolls back if the write is rejected. Pass the car's current
    /// `likeCount` so `displayedLikeCount` can adjust it immediately. Returns
    /// whether the write succeeded. A second tap while one is in flight is
    /// ignored (returns false).
    @discardableResult
    func toggleLike(carId: String, currentLikeCount: Int? = nil) async -> Bool {
        guard let uid = currentUID, pending[carId] == nil else { return false }
        let wasLiked = likedCarIDs.contains(carId)
        let nowLiked = !wasLiked
        let previousBaseline = countBaseline[carId]

        pending[carId] = nowLiked
        if nowLiked { likedCarIDs.insert(carId) } else { likedCarIDs.remove(carId) }
        if let currentLikeCount {
            countBaseline[carId] = (seen: currentLikeCount, delta: nowLiked ? 1 : -1)
        }

        let ref = db.collection("publicCars").document(carId).collection("likes").document(uid)
        do {
            if nowLiked {
                try await ref.setData([
                    "uid": uid,
                    "createdAt": FieldValue.serverTimestamp(),
                ])
            } else {
                try await ref.delete()
            }
            pending[carId] = nil
            return true
        } catch {
            pending[carId] = nil
            guard currentUID == uid else { return false }  // signed out meanwhile
            if wasLiked { likedCarIDs.insert(carId) } else { likedCarIDs.remove(carId) }
            countBaseline[carId] = previousBaseline
            lastError = nowLiked ? "Couldn't like this car." : "Couldn't remove your like."
            print("[LikeStore] toggleLike failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Convenience overload for a `PublicCar` on screen.
    @discardableResult
    func toggleLike(_ car: PublicCar) async -> Bool {
        guard canLike(car) else { return false }
        return await toggleLike(carId: car.carId, currentLikeCount: car.likeCount)
    }

    func clearError() {
        lastError = nil
    }
}
