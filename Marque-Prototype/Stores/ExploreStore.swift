import Foundation
import FirebaseFirestore

struct PublicUserProfile: Codable {
    @DocumentID var uid: String?
    let username: String
    let displayName: String
    let bio: String
    let avatarURL: String
}

@MainActor
class ExploreStore: ObservableObject {
    @Published var cars: [PublicCar] = []
    @Published var isLoading = false

    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    private var profileCache: [String: PublicUserProfile] = [:]

    func startListening() {
        guard listener == nil else { return }
        isLoading = true
        listener = db.collection("publicCars")
            .order(by: "updatedAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.isLoading = false
                self.cars = snapshot.documents.compactMap { try? $0.data(as: PublicCar.self) }
                Task { await self.patchMissingOwnerAvatars() }
            }
    }

    // Back-fills ownerAvatarURL on any publicCars documents that predate the field.
    // Runs after every snapshot; no-ops immediately once all cars have the field.
    private func patchMissingOwnerAvatars() async {
        let carsNeedingAvatar = cars.filter { ($0.ownerAvatarURL ?? "").isEmpty }
        guard !carsNeedingAvatar.isEmpty else { return }

        let uniqueUIDs = Set(carsNeedingAvatar.map { $0.ownerUID })
        for uid in uniqueUIDs {
            guard let profile = await fetchUserProfile(uid: uid),
                  !profile.avatarURL.isEmpty else { continue }
            let carIds = carsNeedingAvatar.filter { $0.ownerUID == uid }.map { $0.carId }
            for carId in carIds {
                try? await db.collection("publicCars").document(carId)
                    .setData(["ownerAvatarURL": profile.avatarURL], merge: true)
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        cars = []
        profileCache = [:]
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
}
