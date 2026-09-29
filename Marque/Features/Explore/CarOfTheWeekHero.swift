import SwiftUI

/// Explore's "Car of the Week" hero: a large, premium feature card shown
/// above Top Cars, "All" category only. Selection (most weekly likes among
/// cars with a photo, falling back to newest-with-a-photo) lives in
/// `ExploreView.heroCar` — this view is purely presentational, wrapped in a
/// `NavigationLink` by the caller (same pattern `ExploreFeedCard` and
/// `TopCarsSection`'s `TopCarCard` use).
struct CarOfTheWeekHero: View {
    let car: PublicCar

    @EnvironmentObject private var likeStore: LikeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private static let cornerRadius: CGFloat = 20

    private var likeCount: Int { likeStore.displayedLikeCount(for: car) }
    private var likesText: String { likeCount == 1 ? "1 like" : "\(likeCount) likes" }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            photo
            scrim
            caption
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(alignment: .topLeading) {
            if car.isNew {
                ExploreNewBadge().padding(12)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
        // Entrance: fade + scale up slightly. Reduce Motion skips straight
        // to the settled state instead of animating into it.
        .scaleEffect(hasAppeared ? 1 : 0.98)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.4)) { hasAppeared = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Car of the Week: \(car.displayName) by @\(car.ownerUsername), \(likesText)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens car details")
    }

    // Square (1:1): of the two ratios in the spec ("about 16:11 or 1:1") this
    // is the more portrait of the two, and full-width at the card's own
    // margins (matching every other section) rather than edge-to-edge, so it
    // reads as a distinctly larger, premium moment above Top Cars.
    private var photo: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { CachedRemoteImage(url: car.primaryPhotoURL) }
    }

    private var scrim: some View {
        LinearGradient(
            colors: [.clear, .clear, .black.opacity(0.75)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            eyebrow
            Text(car.displayName)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(spacing: 6) {
                Text("@\(car.ownerUsername)")
                    .font(.subheadline.weight(.semibold))
                Text("\u{00B7}")
                Text(likesText)
                    .font(.subheadline)
            }
            .foregroundColor(.white.opacity(0.9))
            .lineLimit(1)
        }
        .padding(16)
    }

    private var eyebrow: some View {
        HStack(spacing: 5) {
            Image(systemName: "trophy.fill")
                .font(.caption2)
            Text("CAR OF THE WEEK")
                .font(.caption2.weight(.heavy))
                .kerning(0.6)
        }
        .foregroundColor(.white.opacity(0.95))
    }
}
