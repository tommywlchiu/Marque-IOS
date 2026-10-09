import SwiftUI

/// Palette and chrome for the Garage tab, which is always dark regardless of
/// the system setting (owner decision). Dark is applied locally to the Garage
/// subtree with `.environment(\.colorScheme, .dark)`, never
/// `.preferredColorScheme` (that would flip the whole window).
enum GarageTheme {
    /// Charcoal, not pure black (#16181A).
    static let background = Color(red: 22 / 255, green: 24 / 255, blue: 26 / 255)
    /// Grouped cards and list rows (#222427).
    static let card = Color(red: 34 / 255, green: 36 / 255, blue: 39 / 255)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.56)
    static let tertiaryText = Color.white.opacity(0.4)
    static let icon = Color.white.opacity(0.78)
    static let chevron = Color.white.opacity(0.32)
    static let hairline = Color.white.opacity(0.07)
    /// Used sparingly: the tiny "needs attention" dot. The app's one accent
    /// color (Assets › AccentColor), not a Garage-only blue — so a glance at
    /// any screen reads as the same brand, not a generic default tint.
    static let accentDot = Color.accentColor
}

// MARK: - "Am I inside the Garage tab?"

private struct GarageChromeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside the Garage tab's NavigationStack. Shared screens that are
    /// also used elsewhere (e.g. `ServiceRemindersView`, the sections
    /// extracted from `CarDetailView`) only take the charcoal styling here.
    var isGarageChrome: Bool {
        get { self[GarageChromeKey.self] }
        set { self[GarageChromeKey.self] = newValue }
    }
}

/// Charcoal background + dark nav bar for a screen pushed in the Garage
/// stack. A no-op anywhere else.
private struct GarageScreenChrome: ViewModifier {
    @Environment(\.isGarageChrome) private var isGarageChrome

    func body(content: Content) -> some View {
        if isGarageChrome {
            content
                .scrollContentBackground(.hidden)
                .background(GarageTheme.background.ignoresSafeArea())
                .toolbarBackground(GarageTheme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        } else {
            content
        }
    }
}

/// List-row background for a `Section` that may be shown in the Garage.
private struct GarageRowBackground: ViewModifier {
    @Environment(\.isGarageChrome) private var isGarageChrome

    func body(content: Content) -> some View {
        content.listRowBackground(isGarageChrome ? GarageTheme.card : nil)
    }
}

extension View {
    func garageScreenChrome() -> some View { modifier(GarageScreenChrome()) }
    func garageRowBackground() -> some View { modifier(GarageRowBackground()) }
}
