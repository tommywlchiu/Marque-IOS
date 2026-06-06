import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var exploreStore: ExploreStore
    @EnvironmentObject var followStore: FollowStore
    @EnvironmentObject var blockStore: BlockStore
    @EnvironmentObject var notificationStore: NotificationStore

    @State private var selectedCategory: ExploreCategory = .all
    @State private var profileTarget: ProfileTarget?

    private struct ProfileTarget: Identifiable {
        let uid: String
        let username: String
        var id: String { uid }
    }

    private var visibleCars: [PublicCar] {
        blockStore.filter(exploreStore.cars, ownerUID: \.ownerUID)
    }

    private var filteredCars: [PublicCar] {
        if selectedCategory == .following {
            return followStore.followingFeed(from: visibleCars)
        }
        return selectedCategory.filter(visibleCars)
    }

    var body: some View {
        NavigationStack {
            Group {
                if exploreStore.isLoading && exploreStore.cars.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if exploreStore.cars.isEmpty {
                    MarqueEmptyState(
                        icon: "globe",
                        title: "Nothing Here Yet",
                        subtitle: "Make a car public from its detail screen to share it with the community."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            searchBar
                            categoryPicker
                            if selectedCategory == .all && !visibleCars.isEmpty {
                                featuredSection
                            }
                            if selectedCategory == .following && filteredCars.isEmpty {
                                MarqueEmptyState(
                                    icon: "person.2",
                                    title: "No Cars Yet",
                                    subtitle: "Follow people to see their public cars here."
                                )
                                .padding(.vertical, 40)
                            }
                            gridSection
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: NotificationsInboxView()) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: notificationStore.badgeCount > 0 ? "bell.badge.fill" : "bell")
                                .foregroundColor(notificationStore.badgeCount > 0 ? .accentColor : .primary)
                            if notificationStore.badgeCount > 0 {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -2)
                            }
                        }
                    }
                }
            }
            .sheet(item: $profileTarget) { target in
                NavigationStack {
                    PublicProfileView(ownerUID: target.uid, ownerUsername: target.username)
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        NavigationLink(destination: SearchResultsView().environmentObject(exploreStore)) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                Text("Search cars, makes, or people…").foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ExploreCategory.allCases, id: \.self) { cat in
                    CategoryChip(category: cat, isSelected: selectedCategory == cat) {
                        withAnimation(.spring(duration: 0.25)) { selectedCategory = cat }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Featured

    private var featuredSection: some View {
        VStack(spacing: 12) {
            MarqueSectionHeader(title: "Recently Added").padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(visibleCars.prefix(10)) { car in
                        NavigationLink(destination: CarDetailView(publicCar: car)
                            .environmentObject(exploreStore)
                            .environmentObject(blockStore)) {
                            FeaturedCarCard(car: car) {
                                profileTarget = ProfileTarget(uid: car.ownerUID, username: car.ownerUsername)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Grid

    private var gridSection: some View {
        VStack(spacing: 12) {
            MarqueSectionHeader(
                title: selectedCategory == .all ? "All Cars" : selectedCategory.rawValue
            )
            .padding(.horizontal, 16)

            if filteredCars.isEmpty {
                MarqueEmptyState(
                    icon: "car.fill",
                    title: "No \(selectedCategory.rawValue) Cars",
                    subtitle: "No public cars in this category yet."
                )
                .padding(.vertical, 20)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 14
                ) {
                    ForEach(filteredCars) { car in
                        NavigationLink(destination: CarDetailView(publicCar: car)
                            .environmentObject(exploreStore)
                            .environmentObject(blockStore)) {
                            ExploreCarCell(car: car) {
                                profileTarget = ProfileTarget(uid: car.ownerUID, username: car.ownerUsername)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Category

enum ExploreCategory: String, CaseIterable {
    case following = "Following"
    case all = "All"
    case jdm = "JDM"
    case european = "European"
    case american = "American"
    case electric = "Electric"
    case classic = "Classic"

    func filter(_ cars: [PublicCar]) -> [PublicCar] {
        switch self {
        case .following: return cars // handled in ExploreView directly via followStore
        case .all: return cars
        case .electric:
            return cars.filter { $0.fuelType.lowercased().contains("electric") }
        case .jdm:
            let makes = ["toyota","honda","nissan","mazda","subaru","mitsubishi","lexus","acura","infiniti","suzuki","isuzu","daihatsu"]
            return cars.filter { makes.contains($0.make.lowercased()) }
        case .european:
            let makes = ["bmw","mercedes","audi","volkswagen","porsche","ferrari","lamborghini","maserati","fiat","alfa romeo","volvo","peugeot","renault","citroen","mini","bentley","rolls-royce","bugatti"]
            return cars.filter { makes.contains($0.make.lowercased()) }
        case .american:
            let makes = ["ford","chevrolet","dodge","jeep","cadillac","gmc","lincoln","chrysler","ram","buick","tesla"]
            return cars.filter { makes.contains($0.make.lowercased()) }
        case .classic:
            return cars.filter { (Int($0.year) ?? 2000) < 1990 }
        }
    }
}

// MARK: - Category Chip

private struct CategoryChip: View {
    let category: ExploreCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(category.rawValue)
                .font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Featured Card

private struct FeaturedCarCard: View {
    let car: PublicCar
    var onOwnerTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if car.primaryPhotoURL != nil {
                        CachedRemoteImage(url: car.primaryPhotoURL)
                    } else {
                        noPhotoPlaceholder
                    }
                }
                .frame(width: 200, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                ownerRow.padding(10)
            }
            .frame(width: 200, height: 150)
        }
    }

    @ViewBuilder
    private var ownerRow: some View {
        if let onOwnerTap {
            Button(action: onOwnerTap) { ownerRowContent }
                .buttonStyle(.plain)
        } else {
            ownerRowContent
        }
    }

    private var ownerRowContent: some View {
        HStack(spacing: 6) {
            OwnerAvatar(avatarURL: car.ownerAvatarURL, username: car.ownerUsername, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(car.displayName)
                    .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                Text("@\(car.ownerUsername)")
                    .font(.caption2).foregroundColor(.white.opacity(0.8))
            }
        }
    }

    private var noPhotoPlaceholder: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.1))
            .overlay(Image(systemName: "car.fill").font(.system(size: 40)).foregroundColor(.accentColor.opacity(0.3)))
    }
}

// MARK: - Grid Cell

struct ExploreCarCell: View {
    let car: PublicCar
    var onOwnerTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if car.primaryPhotoURL != nil {
                    CachedRemoteImage(url: car.primaryPhotoURL)
                } else {
                    noPhotoPlaceholder
                }
            }
            .aspectRatio(1.4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            ownerRow
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private var noPhotoPlaceholder: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.08))
            .overlay(Image(systemName: "car.fill").font(.largeTitle).foregroundColor(.accentColor.opacity(0.4)))
    }

    @ViewBuilder
    private var ownerRow: some View {
        if let onOwnerTap {
            Button(action: onOwnerTap) { ownerRowContent }
                .buttonStyle(.plain)
        } else {
            ownerRowContent
        }
    }

    private var ownerRowContent: some View {
        HStack(spacing: 6) {
            OwnerAvatar(avatarURL: car.ownerAvatarURL, username: car.ownerUsername, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(car.displayName)
                    .font(.caption).fontWeight(.semibold).lineLimit(1)
                    .foregroundColor(.primary)
                Text("@\(car.ownerUsername)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
