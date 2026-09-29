import SwiftUI

/// Loading placeholders shown while Explore's first snapshot is still
/// arriving (`exploreStore.isLoading && exploreStore.cars.isEmpty`), and
/// while `TopCarsSection` waits on its own one-shot `loadTopCars` calls.
/// Purely cosmetic — no data, no accessibility content (all hidden from
/// VoiceOver; there's nothing here worth announcing).

// MARK: - Shimmer

/// A gentle left-to-right sweep over skeleton placeholders. Respects Reduce
/// Motion: renders the static grey blocks with no animation at all.
private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.4), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                }
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
        }
        .clipped()
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Feed card skeleton

/// One grey placeholder standing in for `ExploreFeedCard`: header circle +
/// line, a 4:5 photo block, a name line, and an action row.
struct ExploreFeedCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(Color(.systemGray5)).frame(width: 34, height: 34)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 110, height: 12)
                Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemGray5))
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 160, height: 14)
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(width: 44, height: 14)
                RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(width: 44, height: 14)
                Spacer(minLength: 0)
            }
        }
        .shimmering()
        .padding(.horizontal, 16)
    }
}

/// 2-3 stacked feed card skeletons, in the feed's own `28pt` rhythm.
struct ExploreFeedLoadingSkeleton: View {
    var body: some View {
        VStack(spacing: 28) {
            ForEach(0..<3, id: \.self) { _ in
                ExploreFeedCardSkeleton()
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Top Cars skeleton

/// Stand-in for `TopCarsSection`'s carousel while both `loadTopCars` calls
/// are in flight, so the section never renders as bare empty space.
struct TopCarsSkeleton: View {
    private let width: CGFloat = 122
    private var height: CGFloat { width * 5 / 4 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(width: width, height: height)
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(width: width * 0.7, height: 10)
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(width: width * 0.5, height: 8)
                    }
                    .frame(width: width)
                }
            }
            .padding(.horizontal, 16)
        }
        .shimmering()
        .accessibilityHidden(true)
    }
}
