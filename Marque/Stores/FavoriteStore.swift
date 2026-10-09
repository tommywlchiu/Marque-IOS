import Foundation
import FirebaseFirestore

/// Private per-user bookmarks on other users' public cars:
/// `users/{uid}/favorites/{carId}` = `{ createdAt }`. Unlike likes, a
/// favorite carries no public count and nobody but the owner can see their
/// list — it's a personal save-for-later, not a social signal, so it needs
/// no Cloud Function and no cross-user rule (contrast `LikeStore`, which
/// binds the car's own `likes` subcollection).
///
/// Holds the signed-in user's favorited carIds through a direct listener on
/// their own `favorites` subcollection (no collection-group needed — it
/// already lives entirely under their own uid), and resolves each carId to
/// its `PublicCar` on demand, since a favorite can point at a car outside
/// `ExploreStore`'s cached feed window.
@MainActor
final class FavoriteStore: ObservableObject {
    /// carIds (`PublicCar.carId`) the current user has favorited, newest first.
    @Published private(set) var favoritedCarIDs: [String] = []
    /// Resolved cars for `favoritedCarIDs`, keyed by carId. A carId absent
    /// here is either still resolving or no longer resolves (the car was
    /// made private or deleted) — `FavoritesListView` just skips it rather
    /// than showing something broken.
    @Published private(set) var resolvedCars: [String: PublicCar] = [:]
    @Published private(set) var lastError: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var currentUID: String?
    private var resolving: Set<String> = []

    func startListening(uid: String) {
        guard uid != currentUID else { return }
        stopListening()
        currentUID = uid
        listener = db.collection("users").document(uid).collection("favorites")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.currentUID == uid else { return }
                if let error {
                    print("[FavoriteStore] Listener error: \(error.localizedDescription)")
                    return
                }
                guard let snapshot else { return }
                self.favoritedCarIDs = snapshot.documents.map(\.documentID)
                for id in self.favoritedCarIDs where self.resolvedCars[id] == nil {
                    self.resolve(id)
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        currentUID = nil
        favoritedCarIDs = []
        resolvedCars = [:]
        resolving = []
        lastError = nil
    }

    func isFavorited(_ carId: String) -> Bool {
        favoritedCarIDs.contains(carId)
    }

    /// False for the user's own car — favoriting your own car is meaningless.
    func canFavorite(_ car: PublicCar) -> Bool {
        guard let currentUID else { return false }
        return car.ownerUID != currentUID
    }

    /// Favorites or unfavorites `car`. Optimistic: the local list updates
    /// immediately and rolls back if the write is rejected. Returns whether
    /// the write succeeded.
    @discardableResult
    func toggleFavorite(_ car: PublicCar) async -> Bool {
        guard let uid = currentUID, canFavorite(car) else { return false }
        let carId = car.carId
        let wasFavorited = favoritedCarIDs.contains(carId)
        let nowFavorited = !wasFavorited

        if nowFavorited {
            favoritedCarIDs.insert(carId, at: 0)
            resolvedCars[carId] = car
        } else {
            favoritedCarIDs.removeAll { $0 == carId }
        }

        let ref = db.collection("users").document(uid).collection("favorites").document(carId)
        do {
            if nowFavorited {
                try await ref.setData(["createdAt": FieldValue.serverTimestamp()])
            } else {
                try await ref.delete()
            }
            return true
        } catch {
            guard currentUID == uid else { return false }  // signed out meanwhile
            if wasFavorited {
                if !favoritedCarIDs.contains(carId) { favoritedCarIDs.insert(carId, at: 0) }
            } else {
                favoritedCarIDs.removeAll { $0 == carId }
                resolvedCars[carId] = nil
            }
            lastError = nowFavorited ? "Couldn't save this car." : "Couldn't remove this favorite."
            print("[FavoriteStore] toggleFavorite failed: \(error.localizedDescription)")
            return false
        }
    }

    private func resolve(_ carId: String) {
        guard !resolving.contains(carId) else { return }
        resolving.insert(carId)
        Task {
            defer { resolving.remove(carId) }
            guard let doc = try? await db.collection("publicCars").document(carId).getDocument(),
                  let car = try? doc.data(as: PublicCar.self) else { return }
            guard currentUID != nil else { return }
            resolvedCars[carId] = car
        }
    }

    func clearError() {
        lastError = nil
    }
}
