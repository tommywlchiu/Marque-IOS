import SwiftUI

/// The signed-in user's saved cars (`FavoriteStore`), newest first. Reuses
/// `ExploreFeedCard` so a favorited car looks exactly like it does in the
/// main feed — one card component, not a second one to keep in sync.
struct FavoritesListView: View {
    @EnvironmentObject private var favoriteStore: FavoriteStore
    @EnvironmentObject private var exploreStore: ExploreStore
    @EnvironmentObject private var blockStore: BlockStore

    @State private var profileTarget: ProfileTarget?

    private struct ProfileTarget: Identifiable {
        let uid: String
        let username: String
        var id: String { uid }
    }

    /// Resolved, block-filtered, in favorited order. A favorite whose car
    /// hasn't resolved yet (still fetching) or no longer resolves (made
    /// private, or deleted) is skipped rather than shown broken.
    private var cars: [PublicCar] {
        let resolved = favoriteStore.favoritedCarIDs.compactMap { favoriteStore.resolvedCars[$0] }
        return blockStore.filter(resolved, ownerUID: \.ownerUID)
    }

    var body: some View {
        ScrollView {
            if cars.isEmpty {
                MarqueEmptyState(
                    icon: "bookmark",
                    title: "No favorites yet",
                    subtitle: "Tap the bookmark on a car in Explore to save it here."
                )
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 28) {
                    ForEach(cars) { car in
                        NavigationLink(destination: CarDetailView(publicCar: car)
                            .environmentObject(exploreStore)
                            .environmentObject(blockStore)) {
                            ExploreFeedCard(car: car, ownerIsPro: exploreStore.isPro(car.ownerUID), onOwnerTap: {
                                profileTarget = ProfileTarget(uid: car.ownerUID, username: car.ownerUsername)
                            }, onLiked: {})
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $profileTarget) { target in
            NavigationStack {
                PublicProfileView(ownerUID: target.uid, ownerUsername: target.username)
            }
        }
        .modifier(FavoriteErrorAlert())
    }
}
