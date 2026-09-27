import SwiftUI

// MARK: - Garage Entrance Coordinator

/// Arms the "entering the garage" animation for the next time `MainTabView`
/// appears. This is view-layer session state, not a store: it's armed the
/// instant the user actively taps a sign-in/sign-up action (email, Apple, or
/// Google) and consumed the first time the garage is actually reached.
///
/// Deliberately never persisted and never inferred from auth state — `RootView`
/// cannot use `isAuthenticated` flipping false-to-true as the trigger, because
/// `AuthState` starts `.unauthenticated` at every launch and then flips when a
/// restored session's Firebase listener fires, which would replay this on
/// every cold launch. A singleton keeps that arm/consume pair correct across
/// LoginView, SignUpView and RootView without adding an environment object.
@MainActor
final class GarageEntranceCoordinator: ObservableObject {
    static let shared = GarageEntranceCoordinator()

    @Published private(set) var isArmed = false

    private init() {}

    /// Call on tap of Sign In / Continue with Apple / Continue with Google —
    /// on the attempt, not on success. A failed attempt leaves it armed,
    /// which is harmless: the next successful sign-in still plays it once.
    func arm() { isArmed = true }

    /// Atomically checks and clears the arm so `RootView` can't double-fire
    /// it. Returns whether it was armed.
    func consumeIfArmed() -> Bool {
        guard isArmed else { return false }
        isArmed = false
        return true
    }
}

// MARK: - Garage Entrance View

/// Full-screen "entering the garage" overlay played once, the first time
/// `MainTabView` appears after an active sign-in/sign-up this session. A
/// sectional garage door rolls up to reveal the app underneath. Self-removing:
/// the caller supplies `onFinished` and takes the overlay out of the view tree
/// when it's called, so nothing is left behind to intercept touches.
struct GarageEntranceView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var doorOffset: CGFloat = 0
    @State private var lightLeakOpacity: Double = 0
    @State private var lightLeakScale: CGFloat = 1
    @State private var spillOpacity: Double = 0
    @State private var flashOpacity: Double = 0
    @State private var overlayOpacity: Double = 1
    @State private var hasFinished = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                lightSpill.opacity(spillOpacity)

                if reduceMotion {
                    reducedMotionContent
                } else {
                    doorView(size: geo.size)
                        .offset(y: doorOffset)
                }

                Color.white.opacity(flashOpacity)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(overlayOpacity)
            .contentShape(Rectangle())
            .onTapGesture { finish(skipped: true) }
            .task {
                if reduceMotion {
                    await runReducedMotion()
                } else {
                    await runFullSequence(doorHeight: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(!hasFinished)
    }

    // MARK: Door

    /// Height of the soft shadow the door's bottom edge casts on the garage
    /// behind it; the door travels this much further so it clears the screen.
    private static let edgeShadowHeight: CGFloat = 70

    /// One solid door, drawn in a single Canvas and flattened with
    /// `drawingGroup()` so it moves as one GPU texture. It used to be a
    /// VStack of separate slat views with 1pt spacing: the app showed through
    /// every seam as a hairline, and 11 gradient views re-rendered per frame.
    private func doorView(size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            Canvas { context, canvasSize in
                drawDoor(in: &context, size: canvasSize)
            }

            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 130)
                .foregroundStyle(.white.opacity(0.2))
                .shadow(color: .black.opacity(0.6), radius: 0, x: 0, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Light "leaking" under the bottom edge before the door lifts.
            LinearGradient(
                colors: [Color(red: 1, green: 0.82, blue: 0.55).opacity(0.9), .clear],
                startPoint: .bottom, endPoint: .top
            )
            .frame(height: 22)
            .scaleEffect(x: lightLeakScale, y: 1, anchor: .bottom)
            .opacity(lightLeakOpacity)
        }
        .frame(width: size.width, height: size.height)
        .drawingGroup()
        // The shadow the bottom edge throws onto the garage as it rises.
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.edgeShadowHeight)
                .offset(y: Self.edgeShadowHeight)
                .allowsHitTesting(false)
        }
    }

    private func drawDoor(in context: inout GraphicsContext, size: CGSize) {
        let panelCount = 7
        let panelHeight = size.height / CGFloat(panelCount)
        let full = CGRect(origin: .zero, size: size)

        // Solid backing first, so nothing behind the door can ever show.
        context.fill(Path(full), with: .color(Color(white: 0.09)))

        for i in 0..<panelCount {
            let top = CGFloat(i) * panelHeight
            let panel = CGRect(x: 0, y: top, width: size.width, height: panelHeight)

            // Each panel is lit from above: brighter at its top lip, darker
            // where it tucks under the next one.
            context.fill(Path(panel), with: .linearGradient(
                Gradient(colors: [Color(white: 0.24), Color(white: 0.15), Color(white: 0.10)]),
                startPoint: CGPoint(x: 0, y: panel.minY),
                endPoint: CGPoint(x: 0, y: panel.maxY)
            ))

            // Two shallow ribs across each panel, like a real sectional door.
            for rib in [0.34, 0.67] {
                let y = panel.minY + panelHeight * rib
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.28)))
                context.fill(Path(CGRect(x: 0, y: y + 1, width: size.width, height: 1)), with: .color(.white.opacity(0.05)))
            }

            // Seam between panels: a dark joint with a lit lip under it,
            // painted on the solid door (no gap).
            if i > 0 {
                context.fill(Path(CGRect(x: 0, y: top - 1, width: size.width, height: 2)), with: .color(.black.opacity(0.7)))
                context.fill(Path(CGRect(x: 0, y: top + 1, width: size.width, height: 1)), with: .color(.white.opacity(0.14)))
            }
        }

        // Rubber seal along the bottom edge.
        context.fill(Path(CGRect(x: 0, y: size.height - 8, width: size.width, height: 8)), with: .color(Color(white: 0.03)))

        // Subtle side vignette so the door reads as a surface, not a flat fill.
        context.fill(Path(full), with: .linearGradient(
            Gradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.35)]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: 0)
        ))
    }

    private var lightSpill: some View {
        LinearGradient(
            colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.35), Color.clear],
            startPoint: .top, endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var reducedMotionContent: some View {
        ZStack {
            Color.black
            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 110)
                .foregroundStyle(.white)
        }
    }

    // MARK: Sequencing

    private func runFullSequence(doorHeight: CGFloat) async {
        // Phase 1 (0-0.35s): light leaks under the door before it moves.
        AuthHaptics.tap()
        withAnimation(.easeOut(duration: 0.35)) {
            lightLeakOpacity = 1
            lightLeakScale = 1.15
        }
        try? await Task.sleep(for: .seconds(0.35))
        guard !hasFinished else { return }

        // Unlatch: the door settles a few points as the opener takes its
        // weight, which sells the heaviness of what comes next.
        withAnimation(.easeOut(duration: 0.12)) { doorOffset = 5 }
        try? await Task.sleep(for: .seconds(0.12))
        guard !hasFinished else { return }

        // Phase 2: the door rolls up, with a decaying haptic "rumble" and a
        // warm light spill fading in behind it. A slow-start, long-glide curve
        // (a motor spinning up, then the door coasting into the ceiling)
        // instead of a symmetric ease-in-out.
        let rollDuration = 1.15
        withAnimation(.timingCurve(0.5, 0, 0.15, 1, duration: rollDuration)) {
            doorOffset = -(doorHeight + Self.edgeShadowHeight)
        }
        withAnimation(.easeIn(duration: rollDuration * 0.6)) {
            spillOpacity = 1
            lightLeakOpacity = 0
        }
        Task { await runRumble(duration: rollDuration * 0.85) }
        try? await Task.sleep(for: .seconds(rollDuration))
        guard !hasFinished else { return }

        // Phase 3: the spill fades and a brief ceiling-light flash finishes it.
        withAnimation(.easeOut(duration: 0.35)) { spillOpacity = 0 }
        withAnimation(.easeIn(duration: 0.12)) { flashOpacity = 0.1 }
        try? await Task.sleep(for: .seconds(0.12))
        guard !hasFinished else { return }
        withAnimation(.easeOut(duration: 0.25)) { flashOpacity = 0 }
        try? await Task.sleep(for: .seconds(0.25))
        guard !hasFinished else { return }

        finish(skipped: false)
    }

    /// Soft, decaying impacts roughly every 70-90ms while the door lifts.
    /// Self-bounding on `duration`, so it's safe to fire-and-forget: it never
    /// outlives the roll, whether or not this view is still around by then.
    private func runRumble(duration: Double) async {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        var elapsed = 0.0
        var intensity: CGFloat = 1.0
        while elapsed < duration, !hasFinished {
            generator.impactOccurred(intensity: intensity)
            let interval = Double.random(in: 0.07...0.09)
            try? await Task.sleep(for: .seconds(interval))
            elapsed += interval
            intensity = max(0.15, intensity - 0.12)
        }
    }

    private func runReducedMotion() async {
        withAnimation(.easeInOut(duration: 0.4)) { overlayOpacity = 0 }
        try? await Task.sleep(for: .seconds(0.4))
        finish(skipped: false)
    }

    private func finish(skipped: Bool) {
        guard !hasFinished else { return }
        hasFinished = true
        if skipped {
            withAnimation(.easeOut(duration: 0.25)) { overlayOpacity = 0 }
        }
        Task {
            if skipped { try? await Task.sleep(for: .seconds(0.25)) }
            onFinished()
        }
    }
}
