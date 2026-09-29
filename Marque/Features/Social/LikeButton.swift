import SwiftUI

/// Heart + count for a public car. Interactive for everyone but the owner,
/// who sees the count only (the rules deny self-likes; `LikeStore.canLike`).
/// The count comes from `LikeStore.displayedLikeCount`, which bridges the
/// second or two before the server-maintained `likeCount` catches up.
struct LikeButton: View {
    enum Style {
        /// Small heart + count on light card chrome (Explore grid, Top Cars).
        case compact
        /// White heart + count on a material capsule, over a photo.
        case onPhoto
        /// Larger capsule for the car page.
        case prominent
    }

    let car: PublicCar
    var style: Style = .compact
    /// Called after a like (not an unlike) is written successfully, so the
    /// host can offer the push-permission pre-prompt.
    var onLiked: (() -> Void)? = nil

    @EnvironmentObject private var likeStore: LikeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popScale: CGFloat = 1

    private var isLiked: Bool { likeStore.isLiked(car.carId) }
    private var count: Int { likeStore.displayedLikeCount(for: car) }
    private var canLike: Bool { likeStore.canLike(car) }

    var body: some View {
        Group {
            if canLike {
                Button(action: toggle) { label }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isLiked ? "Unlike" : "Like, \(likesText)")
                    .accessibilityValue(isLiked ? likesText : "")
                    .accessibilityAddTraits(isLiked ? .isSelected : [])
            } else {
                // Owner view: count only, never a control.
                label
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(likesText)
            }
        }
    }

    private var likesText: String {
        count == 1 ? "1 like" : "\(count) likes"
    }

    private var heartName: String {
        (isLiked || !canLike) ? "heart.fill" : "heart"
    }

    private var heartColor: Color {
        if isLiked { return .red }
        switch style {
        case .onPhoto: return .white
        case .compact, .prominent: return canLike ? .secondary : .red.opacity(0.7)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .compact:
            HStack(spacing: 3) {
                heart.font(.caption)
                Text(count.formatted())
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        case .onPhoto:
            HStack(spacing: 4) {
                heart.font(.caption)
                Text(count.formatted())
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
            .environment(\.colorScheme, .dark)
            .contentShape(Capsule())
        case .prominent:
            HStack(spacing: 6) {
                heart.font(.title3)
                Text(count.formatted())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                Capsule().fill(isLiked ? Color.red.opacity(0.1) : Color(.systemGray6))
            )
            .contentShape(Capsule())
        }
    }

    private var heart: some View {
        Image(systemName: heartName)
            .foregroundColor(heartColor)
            .scaleEffect(popScale)
    }

    private func toggle() {
        let willLike = !isLiked
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if willLike && !reduceMotion {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { popScale = 1.35 }
            Task {
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { popScale = 1 }
            }
        }
        Task {
            let ok = await likeStore.toggleLike(car)
            if ok && willLike { onLiked?() }
        }
    }
}

/// Alert for a rejected like/unlike (`LikeStore.lastError`). Attach once per
/// screen that shows `LikeButton`s.
struct LikeErrorAlert: ViewModifier {
    @EnvironmentObject private var likeStore: LikeStore

    func body(content: Content) -> some View {
        content.alert(
            "Couldn't update like",
            isPresented: Binding(
                get: { likeStore.lastError != nil },
                set: { if !$0 { likeStore.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { likeStore.clearError() }
        } message: {
            Text(likeStore.lastError ?? "")
        }
    }
}
