import SwiftUI

/// Explore's "Top Cars": most-liked public cars, This Week / All Time, as
/// ranked cards. `ExploreStore`'s lists aren't block-filtered, so they go
/// through `BlockStore.filter` here, and ranks are positions in the
/// filtered list.
struct TopCarsSection: View {
    var onOwnerTap: (PublicCar) -> Void
    var onLiked: () -> Void

    @EnvironmentObject private var exploreStore: ExploreStore
    @EnvironmentObject private var blockStore: BlockStore
    @State private var period: TopCarsPeriod = .thisWeek

    static let displayLimit = 10

    private var ranked: [PublicCar] {
        Array(blockStore.filter(exploreStore.topCars(period), ownerUID: \.ownerUID).prefix(Self.displayLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarqueSectionHeader(title: "Top Cars")
                .padding(.horizontal, 16)

            Picker("Period", selection: $period) {
                ForEach(TopCarsPeriod.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            content
        }
        .task(id: period) {
            await exploreStore.loadTopCars(period)
        }
    }

    @ViewBuilder
    private var content: some View {
        let cars = ranked
        if cars.isEmpty && exploreStore.isLoadingTopCars {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 150)
        } else if cars.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "heart")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(period == .thisWeek ? "No likes yet this week" : "No likes yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Tap the heart on a car you love to put it on the board.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
            .padding(.horizontal, 16)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(cars.enumerated()), id: \.element.carId) { index, car in
                        NavigationLink(destination: CarDetailView(publicCar: car)) {
                            TopCarCard(
                                car: car,
                                rank: index + 1,
                                period: period,
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
}

private struct TopCarCard: View {
    let car: PublicCar
    let rank: Int
    let period: TopCarsPeriod
    let onOwnerTap: () -> Void
    let onLiked: () -> Void

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
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let url = car.primaryPhotoURL {
                        CachedRemoteImage(url: url)
                    } else {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.1))
                            .overlay(
                                Image(systemName: "car.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.accentColor.opacity(0.3))
                            )
                    }
                }
                .frame(width: 220, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Text("#\(rank)")
                    .font(.subheadline.weight(.heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(rankColor))
                    .padding(8)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                LikeButton(car: car, style: .onPhoto, onLiked: onLiked)
                    .padding(8)
            }

            Button(action: onOwnerTap) {
                HStack(spacing: 6) {
                    OwnerAvatar(avatarURL: car.ownerAvatarURL, username: car.ownerUsername, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(car.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rank \(rank), \(car.displayName) by @\(car.ownerUsername), \(countText)")
        }
        .frame(width: 220)
    }

    private var countText: String {
        let noun = periodCount == 1 ? "like" : "likes"
        return period == .thisWeek ? "\(periodCount) \(noun) this week" : "\(periodCount) \(noun)"
    }

    private var subtitle: String {
        "@\(car.ownerUsername) · \(countText)"
    }
}
