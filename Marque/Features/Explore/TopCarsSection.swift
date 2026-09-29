import SwiftUI

/// Explore's "Top Cars": a compact horizontal carousel of the most-liked
/// public cars, This Week / All Time. `ExploreStore`'s lists aren't
/// block-filtered, so they go through `BlockStore.filter` here, and ranks
/// are positions in the filtered list.
///
/// If This Week has no cars (after filtering) it falls back to All Time
/// automatically, with a caption explaining why. If both are empty, the
/// whole section renders as nothing.
struct TopCarsSection: View {
    var onOwnerTap: (PublicCar) -> Void
    var onLiked: () -> Void

    @EnvironmentObject private var exploreStore: ExploreStore
    @EnvironmentObject private var blockStore: BlockStore
    @State private var selectedPeriod: TopCarsPeriod = .thisWeek
    @State private var hasLoadedOnce = false
    /// Bumped on reappear to retry `loadTopCars` once more when both lists
    /// are still empty after the first load — see the `.task(id:)` below.
    /// `ExploreStore.loadTopCars` swallows its own errors (`try?`), so a
    /// genuinely-empty result and a dropped request are indistinguishable
    /// here; this is a best-effort retry, not a real error path.
    @State private var reloadToken = 0

    static let displayLimit = 10

    private func ranked(_ period: TopCarsPeriod) -> [PublicCar] {
        Array(blockStore.filter(exploreStore.topCars(period), ownerUID: \.ownerUID).prefix(Self.displayLimit))
    }

    private var thisWeekRanked: [PublicCar] { ranked(.thisWeek) }
    private var allTimeRanked: [PublicCar] { ranked(.allTime) }

    /// Falls back to All Time when This Week is selected but empty and All
    /// Time has cars; otherwise honors the user's explicit choice.
    private var effectivePeriod: TopCarsPeriod {
        if selectedPeriod == .thisWeek && thisWeekRanked.isEmpty && !allTimeRanked.isEmpty {
            return .allTime
        }
        return selectedPeriod
    }

    private var isAutoFallback: Bool {
        selectedPeriod == .thisWeek && effectivePeriod == .allTime
    }

    private var displayedCars: [PublicCar] { ranked(effectivePeriod) }

    var body: some View {
        Group {
            if hasLoadedOnce && thisWeekRanked.isEmpty && allTimeRanked.isEmpty {
                EmptyView()
            } else {
                content
            }
        }
        .task(id: reloadToken) {
            // Load both up front (not just the selected period): needed to
            // know whether This Week is empty (for the fallback) and to make
            // switching periods with the header control instant.
            async let week: () = exploreStore.loadTopCars(.thisWeek)
            async let allTime: () = exploreStore.loadTopCars(.allTime)
            _ = await (week, allTime)
            hasLoadedOnce = true
        }
        .onAppear {
            // Retry once per reappearance if the first load came back with
            // nothing at all (not just "no likes yet this week" — both
            // periods empty). Guards against a dropped request rather than a
            // genuinely quiet week; see `reloadToken`'s doc comment.
            if hasLoadedOnce && thisWeekRanked.isEmpty && allTimeRanked.isEmpty {
                reloadToken += 1
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !hasLoadedOnce {
                TopCarsSkeleton()
            } else {
                if isAutoFallback {
                    Text("No likes this week yet — showing all-time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                }
                carousel
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Top Cars")
                .font(.headline).fontWeight(.semibold)
            Spacer(minLength: 0)
            periodControl
        }
        .padding(.horizontal, 16)
    }

    /// Compact in-header This Week / All Time switch (not a full-width bar).
    private var periodControl: some View {
        HStack(spacing: 2) {
            ForEach(TopCarsPeriod.allCases) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedPeriod = period }
                } label: {
                    Text(period.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(
                            selectedPeriod == period ? Color(.systemBackground) : Color.clear,
                            in: Capsule()
                        )
                        .foregroundColor(selectedPeriod == period ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedPeriod == period ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(.systemGray6)))
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(displayedCars.enumerated()), id: \.element.carId) { index, car in
                    NavigationLink(destination: CarDetailView(publicCar: car)) {
                        TopCarCard(
                            car: car,
                            rank: index + 1,
                            period: effectivePeriod,
                            onOwnerTap: { onOwnerTap(car) },
                            onLiked: onLiked
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }
}

private struct TopCarCard: View {
    let car: PublicCar
    let rank: Int
    let period: TopCarsPeriod
    let onOwnerTap: () -> Void
    let onLiked: () -> Void

    private static let thumbWidth: CGFloat = 122
    private static let thumbHeight: CGFloat = thumbWidth * 5 / 4

    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 0.85, green: 0.65, blue: 0.13)
        case 2: return Color(red: 0.55, green: 0.58, blue: 0.62)
        case 3: return Color(red: 0.72, green: 0.45, blue: 0.2)
        default: return Color.black.opacity(0.6)
        }
    }

    private var periodCount: Int { period.count(of: car) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                photoThumb

                Text("#\(rank)")
                    .font(.caption2.weight(.heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(rankColor))
                    .padding(6)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                LikeButton(car: car, style: .onPhoto, onLiked: onLiked)
                    .padding(6)
            }

            Button(action: onOwnerTap) {
                HStack(spacing: 5) {
                    OwnerAvatar(avatarURL: car.ownerAvatarURL, username: car.ownerUsername, size: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(car.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(countText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rank \(rank), \(car.displayName) by @\(car.ownerUsername), \(countText)")
        }
        .frame(width: Self.thumbWidth)
    }

    private var photoThumb: some View {
        Group {
            if let url = car.primaryPhotoURL {
                CachedRemoteImage(url: url)
                    .frame(width: Self.thumbWidth, height: Self.thumbHeight)
            } else {
                ExploreNoPhotoPlaceholder(make: car.make, model: car.model, iconSize: 28, showsLabel: false)
                    .frame(width: Self.thumbWidth, height: Self.thumbHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var countText: String {
        let noun = periodCount == 1 ? "like" : "likes"
        return period == .thisWeek ? "\(periodCount) \(noun) this week" : "\(periodCount) \(noun)"
    }
}
