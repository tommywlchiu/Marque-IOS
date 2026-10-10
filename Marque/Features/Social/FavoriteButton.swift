import SwiftUI

/// Bookmark toggle for a public car: a private save, no count, no one else
/// ever sees it (contrast `LikeButton`, a public signal with a server count).
/// Hidden for the car's own owner — saving your own car is meaningless.
struct FavoriteButton: View {
    enum Style {
        /// Larger capsule for the car page, alongside `LikeButton`.
        case prominent
        /// Small icon on light card chrome (a favorites list row).
        case compact
    }

    let car: PublicCar
    var style: Style = .prominent

    @EnvironmentObject private var favoriteStore: FavoriteStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popScale: CGFloat = 1

    private var isFavorited: Bool { favoriteStore.isFavorited(car.carId) }

    var body: some View {
        if favoriteStore.canFavorite(car) {
            Button(action: toggle) { label }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorited ? "Remove from favorites" : "Save to favorites")
                .accessibilityAddTraits(isFavorited ? .isSelected : [])
        }
    }

    private var iconName: String { isFavorited ? "bookmark.fill" : "bookmark" }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .prominent:
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(isFavorited ? .accentColor : .primary)
                .scaleEffect(popScale)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(isFavorited ? Color.accentColor.opacity(0.1) : Color(.systemGray6)))
                .contentShape(Capsule())
        case .compact:
            Image(systemName: iconName)
                .font(.caption)
                .foregroundColor(isFavorited ? .accentColor : .secondary)
                .scaleEffect(popScale)
                .padding(.vertical, 6).padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
    }

    private func toggle() {
        let willFavorite = !isFavorited
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if willFavorite && !reduceMotion {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { popScale = 1.3 }
            Task {
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { popScale = 1 }
            }
        }
        Task { await favoriteStore.toggleFavorite(car) }
    }
}

/// Alert for a rejected favorite/unfavorite (`FavoriteStore.lastError`).
/// Attach once per screen that shows `FavoriteButton`s.
struct FavoriteErrorAlert: ViewModifier {
    @EnvironmentObject private var favoriteStore: FavoriteStore

    func body(content: Content) -> some View {
        content.alert(
            "Couldn't update favorites",
            isPresented: Binding(
                get: { favoriteStore.lastError != nil },
                set: { if !$0 { favoriteStore.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { favoriteStore.clearError() }
        } message: {
            Text(favoriteStore.lastError ?? "")
        }
    }
}
