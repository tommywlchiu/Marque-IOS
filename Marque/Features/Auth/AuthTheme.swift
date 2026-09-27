import SwiftUI

// MARK: - Showroom Theme
//
// Shared visual language for the login/sign-up screens: a dark, premium
// "automotive showroom" look that's forced via `.environment(\.colorScheme,
// .dark)` on each screen's root (never `.preferredColorScheme`, which would
// leak the dark appearance into the rest of the app). Everything here uses
// explicit colors rather than adaptive system ones, since it's always
// rendered against the same near-black background regardless of the
// device's actual appearance setting.

private extension Color {
    /// Gradient endpoints for the showroom background — near-black with a
    /// faint cool (blue) tint at the top, fading to true black.
    static let showroomTop = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x10 / 255)
    static let showroomBottom = Color.black
}

// MARK: - Background

/// Full-bleed dark gradient plus a single soft "showroom light" behind the
/// logo that breathes on a long, low-opacity loop. Deliberately just one
/// light source — more would read as busy rather than premium.
struct ShowroomBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.showroomTop, .showroomBottom], startPoint: .top, endPoint: .bottom)

            RadialGradient(
                colors: [Color.white.opacity(breathing ? 0.25 : 0.15), .clear],
                center: UnitPoint(x: 0.5, y: 0.24),
                startRadius: 20,
                endRadius: 320
            )
            .blur(radius: 50)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

// MARK: - Logo

/// The brand mark, tinted white (it's a template image), with a one-time
/// glossy "shine" sweep shortly after appearing and a slow, occasional
/// repeat so it reads as polish rather than a loading indicator.
struct LogoMarkWithShine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepOn = false

    var body: some View {
        Image("LogoMark")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .overlay {
                if !reduceMotion {
                    shine
                }
            }
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(0.9))
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 1.0)) { sweepOn = true }
                    try? await Task.sleep(for: .seconds(1.0))
                    sweepOn = false
                    try? await Task.sleep(for: .seconds(6.5))
                }
            }
            .accessibilityLabel("Marque")
    }

    private var shine: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(colors: [.clear, .white.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: w * 0.4)
                .rotationEffect(.degrees(18))
                .offset(x: sweepOn ? w * 1.4 : -w * 1.4)
                .blendMode(.plusLighter)
        }
        .mask(Image("LogoMark").resizable().scaledToFit())
        .allowsHitTesting(false)
    }
}

// MARK: - Staggered Entrance

/// Fades and slides content up on first appearance, with a per-index delay so
/// a stack of sibling views (fields, button, divider, social row, footer)
/// reads as a single staggered cascade rather than popping in together.
private struct StaggeredAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .onAppear {
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.25)
                    : .easeOut(duration: 0.5).delay(Double(index) * 0.06)
                withAnimation(animation) { appeared = true }
            }
    }
}

extension View {
    /// `index` is this view's position in the stagger sequence (0-based),
    /// not a z-index or tag — only the ordering/spacing between calls matters.
    func staggeredAppear(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

// MARK: - Glass Field Chrome

/// Dark "glass" chrome for a text field row: translucent white fill, a
/// hairline stroke that brightens with a soft glow on focus. Apply to an
/// `HStack` containing a leading SF Symbol + `TextField`/`SecureField`, not
/// to the field alone, so the icon sits inside the same glass surface.
struct AuthFieldChrome: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor : Color.white.opacity(0.12), lineWidth: isFocused ? 1.5 : 1)
            )
            .shadow(color: isFocused ? Color.accentColor.opacity(0.35) : .clear, radius: isFocused ? 10 : 0)
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

extension View {
    func authFieldChrome(isFocused: Bool) -> some View {
        modifier(AuthFieldChrome(isFocused: isFocused))
    }
}

// MARK: - Primary Capsule Button

/// A dedicated white-capsule/black-text button for the auth screens' primary
/// action. `MarquePrimaryButton` is styled for the app's accent-tinted look
/// used everywhere else (Settings, Onboarding, ...); this is scoped to Login
/// and Sign Up rather than a change to that shared component.
struct AuthPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(.black)
                } else {
                    Text(title).font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
        }
        .buttonStyle(AuthCapsuleButtonStyle())
        .disabled(isLoading)
    }
}

private struct AuthCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .background(Color.white)
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Error Banner

/// Wraps the shared `MarqueErrorBanner` (used elsewhere in light contexts, so
/// not restyled itself) in chrome that reads correctly against the dark
/// showroom background, and gives it a distinct appear/disappear transition.
struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        MarqueErrorBanner(message: message)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Haptics

enum AuthHaptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
