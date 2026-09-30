import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var exploreStore: ExploreStore
    @EnvironmentObject var followStore: FollowStore
    @EnvironmentObject var blockStore: BlockStore
    @EnvironmentObject var notificationStore: NotificationStore

    @State private var selectedCategory: ExploreCategory = .all
    @State private var profileTarget: ProfileTarget?
    @State private var showingPushPrePrompt = false
    @AppStorage("marque_explore_sort") private var sortRaw: String = ExploreSort.newest.rawValue
    /// Like counts captured when "Most liked" order was last computed. The
    /// feed sorts on these, not the live counts, so a like anywhere in the
    /// 100 cached cars can't reshuffle the feed under the user's thumb. Taken
    /// on appear, on sort change, on pull-to-refresh, and when the set of
    /// cars changes (a new or removed car, not a count change).
    @State private var likeSnapshot: [String: Int] = [:]
    /// Set once (either automatically or by a manual chip tap) so the
    /// "Following" default-category logic never runs again this session —
    /// see `applyDefaultCategoryOnce()`.
    @State private var defaultCategoryDecided = false
    /// Temporary "popular now" model filter, set by tapping a
    /// `PopularModelsRow` chip and cleared via `ActiveModelFilterChip`.
    /// Applied on top of the category filter in `filteredCars`.
    @State private var modelFilter: CarTaxonomy.PopularModelGroup?

    private struct ProfileTarget: Identifiable {
        let uid: String
        let username: String
        var id: String { uid }
    }

    private var sort: ExploreSort { ExploreSort(rawValue: sortRaw) ?? .newest }

    private var visibleCars: [PublicCar] {
        blockStore.filter(exploreStore.cars, ownerUID: \.ownerUID)
    }

    // MARK: - Car of the Week

    /// Cars eligible for the hero: block-filtered, and must have at least
    /// one photo (a photo-less hero would just show the placeholder art,
    /// which isn't "a large, premium card"). `visibleCars` is already
    /// newest-first (ExploreStore orders by `updatedAt` descending).
    private var heroCandidates: [PublicCar] {
        visibleCars.filter { !$0.galleryURLs.isEmpty }
    }

    /// Most `weeklyLikeCount` among `heroCandidates`, ties broken by newest
    /// (a stable sort over the already newest-first list). Falls back to
    /// the newest candidate outright when nobody has any weekly likes.
    /// `nil` hides the hero entirely (no candidate has a photo).
    private var heroCar: PublicCar? {
        heroCandidates.sorted { $0.weeklyLikeCount > $1.weeklyLikeCount }.first
    }

    /// Cars currently loaded, block-filtered, grouped into ≥2-car "popular
    /// now" models (see `PopularModelsRow`). Computed from `visibleCars`
    /// directly — independent of `selectedCategory` — so the row reflects
    /// the whole feed, not just the currently selected chip.
    private var popularModelGroups: [CarTaxonomy.PopularModelGroup] {
        CarTaxonomy.popularModelGroups(from: visibleCars)
    }

    private var filteredCars: [PublicCar] {
        let base: [PublicCar]
        if selectedCategory == .following {
            base = followStore.followingFeed(from: visibleCars)
        } else {
            let categoryFiltered = selectedCategory.filter(visibleCars)
            // The hero already features this car above the feed; always leave
            // it out of the "All" list rather than only when sort/category
            // are at their defaults, so it can never appear twice on screen
            // regardless of how the user has the feed sorted.
            if selectedCategory == .all, let heroCar {
                base = categoryFiltered.filter { $0.carId != heroCar.carId }
            } else {
                base = categoryFiltered
            }
        }
        guard let modelFilter else { return base }
        return base.filter { CarTaxonomy.squash($0.make) + CarTaxonomy.squash($0.model) == modelFilter.id }
    }

    // ExploreStore.cars is already ordered newest-first (`updatedAt`
    // descending), and every filter above preserves order, so "Newest" is
    // just `filteredCars`. "Most liked" re-sorts on likeCount, falling back
    // to that same newest-first order on ties (Array.sorted is stable).
    private var sortedFilteredCars: [PublicCar] {
        let base: [PublicCar]
        switch sort {
        case .newest:
            base = filteredCars
        case .mostLiked:
            base = filteredCars.sorted {
                (likeSnapshot[$0.carId] ?? $0.likeCount) > (likeSnapshot[$1.carId] ?? $1.likeCount)
            }
        }
        // Photo-less cars sink to the end in both sorts, keeping their
        // relative order within each group (`filter` preserves order).
        return base.filter { !$0.galleryURLs.isEmpty } + base.filter { $0.galleryURLs.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if exploreStore.isLoading && exploreStore.cars.isEmpty {
                    ScrollView {
                        VStack(spacing: 24) {
                            TopCarsSkeleton()
                            ExploreFeedLoadingSkeleton()
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                    }
                } else if exploreStore.cars.isEmpty {
                    MarqueEmptyState(
                        icon: "globe",
                        title: "Nothing Here Yet",
                        subtitle: "Make a car public from its detail screen to share it with the community."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            searchBar
                            categoryPicker
                            if let modelFilter {
                                ActiveModelFilterChip(group: modelFilter) {
                                    withAnimation(.spring(duration: 0.25)) { self.modelFilter = nil }
                                }
                            } else {
                                PopularModelsRow(groups: popularModelGroups) { group in
                                    withAnimation(.spring(duration: 0.25)) { modelFilter = group }
                                }
                            }
                            if selectedCategory == .all, let heroCar {
                                NavigationLink(destination: CarDetailView(publicCar: heroCar)
                                    .environmentObject(exploreStore)
                                    .environmentObject(blockStore)) {
                                    CarOfTheWeekHero(car: heroCar)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                            }
                            if selectedCategory == .all && !visibleCars.isEmpty {
                                TopCarsSection(
                                    onOwnerTap: { car in
                                        profileTarget = ProfileTarget(uid: car.ownerUID, username: car.ownerUsername)
                                    },
                                    onLiked: offerPushPrePrompt
                                )
                            }
                            feedSection
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        await exploreStore.refresh()
                        takeLikeSnapshot()
                        await exploreStore.loadTopCars(.thisWeek)
                        await exploreStore.loadTopCars(.allTime)
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
            // Not offered on Explore: the Garage tab's button folds away here
            // as the user switches tabs (see AskMarqueDock).
            .overlay(alignment: .bottomTrailing) {
                AskMarqueDock(mode: .tuckAway)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .pushPrePrompt(isPresented: $showingPushPrePrompt)
            .onAppear {
                takeLikeSnapshot()
                applyDefaultCategoryOnce()
            }
            .onChange(of: sortRaw) { _, _ in takeLikeSnapshot() }
            .onChange(of: exploreStore.cars.map(\.carId)) { _, _ in takeLikeSnapshot() }
        }
        // On the stack, not its root, so it can present over a pushed car page.
        .modifier(LikeErrorAlert())
        .modifier(FollowPushRouter())
    }

    private func takeLikeSnapshot() {
        likeSnapshot = Dictionary(
            exploreStore.cars.map { ($0.carId, $0.likeCount) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// FR: "Following" is the default category when the user follows at
    /// least one person with a public car; otherwise "All" stays the
    /// default. Decided once per session, on first appearance — guarded by
    /// `defaultCategoryDecided`, which a manual chip tap also sets (see
    /// `categoryPicker`) so this can never override the user's own choice.
    /// Both stores' listeners are started well before Explore is reachable
    /// (at auth-state change, in `Marque_PrototypeApp`), so `visibleCars`
    /// and `followStore.followingUIDs` are expected to already be populated
    /// by the time this fires.
    private func applyDefaultCategoryOnce() {
        guard !defaultCategoryDecided else { return }
        defaultCategoryDecided = true
        if !followStore.followingFeed(from: visibleCars).isEmpty {
            selectedCategory = .following
        }
    }

    private func offerPushPrePrompt() {
        PushPrePrompt.offer { showingPushPrePrompt = true }
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
                        // A manual pick, even to "Following" itself, retires
                        // the default-category logic for the rest of the
                        // session (see `applyDefaultCategoryOnce()`).
                        defaultCategoryDecided = true
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        // Fades the trailing edge so it's obvious the row scrolls further,
        // rather than looking like it's cut off (Explore redesign issue #5).
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // MARK: - Feed

    /// The main feed: one full-width card per car (Explore redesign — replaces
    /// the old two-column grid, which overlapped and had uneven row heights).
    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            feedHeader

            if filteredCars.isEmpty {
                let following = selectedCategory == .following
                MarqueEmptyState(
                    icon: following ? "person.2" : "car.fill",
                    title: modelFilter != nil
                        ? "No \(modelFilter!.model) Cars"
                        : (following ? "No Cars Yet" : selectedCategory.emptyStateTitle),
                    subtitle: modelFilter != nil
                        ? "No public \(modelFilter!.model) in this category right now."
                        : (following
                            ? "Follow people to see their public cars here."
                            : "No public cars in this category yet.")
                )
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 28) {
                    ForEach(sortedFilteredCars) { car in
                        NavigationLink(destination: CarDetailView(publicCar: car)
                            .environmentObject(exploreStore)
                            .environmentObject(blockStore)) {
                            ExploreFeedCard(car: car, onOwnerTap: {
                                profileTarget = ProfileTarget(uid: car.ownerUID, username: car.ownerUsername)
                            }, onLiked: offerPushPrePrompt)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private var feedHeader: some View {
        HStack {
            Text(selectedCategory == .all ? "All Cars" : selectedCategory.rawValue)
                .font(.headline).fontWeight(.semibold)
            Spacer(minLength: 0)
            Menu {
                Picker("Sort", selection: $sortRaw) {
                    Text(ExploreSort.newest.label).tag(ExploreSort.newest.rawValue)
                    Text(ExploreSort.mostLiked.label).tag(ExploreSort.mostLiked.rawValue)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sort.label)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .accessibilityLabel("Sort: \(sort.label)")
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Sort

enum ExploreSort: String {
    case newest
    case mostLiked

    var label: String {
        switch self {
        case .newest: return "Newest"
        case .mostLiked: return "Most liked"
        }
    }
}

// MARK: - Category

enum ExploreCategory: String, CaseIterable {
    case following = "Following"
    case all = "All"
    // Ordered right after "All", before JDM, per the Explore redesign spec.
    case supercars = "Supercars"
    case modified = "Modified"
    case jdm = "JDM"
    case european = "European"
    case american = "American"
    case electric = "Electric"
    case classic = "Classic"

    // All categorization logic (make lists, supercar rules, the classic
    // year cutoff) lives in `CarTaxonomy` now, so this is just wiring.
    // Categories are independent of each other on purpose — a Ferrari can
    // be both Supercars and European; nothing here excludes Supercars from
    // another category's results.
    func filter(_ cars: [PublicCar]) -> [PublicCar] {
        switch self {
        case .following: return cars // handled in ExploreView directly via followStore
        case .all: return cars
        case .supercars:
            return cars.filter { CarTaxonomy.isSupercar(make: $0.make, model: $0.model, trim: $0.trim) }
        case .modified:
            return cars.filter { $0.isModified }
        case .electric:
            return cars.filter { $0.fuelType.lowercased().contains("electric") }
        case .jdm:
            return cars.filter { CarTaxonomy.isJDM(make: $0.make) }
        case .european:
            return cars.filter { CarTaxonomy.isEuropean(make: $0.make) }
        case .american:
            return cars.filter { CarTaxonomy.isAmerican(make: $0.make) }
        case .classic:
            return cars.filter { CarTaxonomy.isClassic(year: $0.year) }
        }
    }

    /// The feed's empty-state title for this category (`following` isn't
    /// used here -- `ExploreView` special-cases it to "No Cars Yet"). Reads
    /// naturally per category rather than the old generic "No \(rawValue)
    /// Cars", which produced "No Supercars Cars".
    var emptyStateTitle: String {
        switch self {
        case .following, .all: return "No Cars Yet"
        case .supercars: return "No Supercars Yet"
        case .modified: return "No Modified Cars Yet"
        case .jdm: return "No JDM Cars Yet"
        case .european: return "No European Cars Yet"
        case .american: return "No American Cars Yet"
        case .electric: return "No Electric Cars Yet"
        case .classic: return "No Classic Cars Yet"
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
                .overlay(
                    Capsule().stroke(Color.primary.opacity(isSelected ? 0 : 0.06), lineWidth: 1)
                )
                .shadow(color: isSelected ? Color.accentColor.opacity(0.35) : .clear, radius: 6, x: 0, y: 3)
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Grid Cell
//
// Still used by `PublicProfileView`'s own car grid; the main Explore feed
// no longer uses this (see `ExploreFeedCard`).

struct ExploreCarCell: View {
    let car: PublicCar
    var onOwnerTap: (() -> Void)? = nil
    var onLiked: (() -> Void)? = nil

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

            HStack(spacing: 4) {
                ownerRow
                LikeButton(car: car, style: .compact, onLiked: onLiked)
            }
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
