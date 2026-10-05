import Foundation

/// The owner's own car as the public sees it. Shared by CarDetailView and
/// the Garage (share card, likes/comments row).
@MainActor
enum OwnCarPublicProjection {
    /// The published `publicCars` copy, if Explore has it loaded.
    static func publishedCopy(of car: Car, in exploreStore: ExploreStore) -> PublicCar? {
        guard car.isPublic else { return nil }
        let id = car.id.uuidString
        return exploreStore.cars.first(where: { $0.carId == id })
            ?? exploreStore.topCarsAllTime.first(where: { $0.carId == id })
    }

    /// The FR-06.3 public projection `ShareCardSheet` / `CarShareCard` are
    /// built from — structurally the same privacy boundary as everything else
    /// that reaches Explore. Prefers the live `publicCars` copy (real server
    /// valueRange / likeCount) over a freshly built one; for a private car
    /// there's no published doc yet, so `PublicCar(from:)` is built directly
    /// (its valueRange is nil, which is correct — nothing has been computed
    /// server-side for it). nil only when signed out.
    static func shareCard(for car: Car, exploreStore: ExploreStore, authService: AuthService) -> PublicCar? {
        if let published = publishedCopy(of: car, in: exploreStore) { return published }
        guard let user = authService.currentUser else { return nil }
        return PublicCar(
            from: car,
            ownerUID: user.id,
            ownerUsername: user.username,
            ownerAvatarURL: user.avatarURL
        )
    }
}
