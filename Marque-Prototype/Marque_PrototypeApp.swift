import SwiftUI
import FirebaseAppCheck
import FirebaseCore
import FirebaseFirestore

/// Process launch time, for `app_launch_completed` (FR-11.4). A Swift global is
/// initialized lazily on first access; this is first touched in the App's init,
/// so it lands as close to process start as we can get without an @main hook.
private let launchStartedAt = Date()

/// Owns `app_opened.is_first_open` (FR-11.4). Lives at the call site rather than
/// in AnalyticsService: it's launch state, not analytics plumbing, and putting it
/// here keeps AnalyticsService free of persistence concerns.
private enum LaunchState {
    private static let hasLaunchedKey = "marque_has_launched_before"

    /// True exactly once per install. Reading it marks the install as launched.
    static func consumeIsFirstOpen() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: hasLaunchedKey) { return false }
        defaults.set(true, forKey: hasLaunchedKey)
        return true
    }
}

/// Chooses the App Check provider. App Attest does not run in the Simulator, so
/// the Simulator gets the debug provider (its token must be registered in the
/// Firebase console before it validates). This is keyed on the Simulator, NOT on
/// `DEBUG`, on purpose: a Debug build on a real device should exercise App
/// Attest, and a Release build must never fall back to the debug provider.
///
/// Registered before `FirebaseApp.configure()`. If a token can't be obtained
/// (console not set up, attestation failure), the Functions SDK still sends
/// the call with a placeholder token rather than blocking it.
final class MarqueAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        // Failable: nil if the FirebaseApp options are incomplete. iOS 14+ only,
        // which the iOS 17.6 deployment target already guarantees.
        return AppAttestProvider(app: app)
        #endif
    }
}

@main
struct Marque_PrototypeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var carStore = CarStore()
    @StateObject private var authService = AuthService()
    @StateObject private var exploreStore = ExploreStore()
    @StateObject private var followStore = FollowStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var blockStore = BlockStore()
    @StateObject private var notificationStore = NotificationStore()
    @StateObject private var chatStore = ChatStore()
    @StateObject private var scanAllowanceStore = ScanAllowanceStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()

    init() {
        _ = launchStartedAt  // force the global's lazy init as early as possible
        // Must precede configure(): App Check reads the factory when Firebase starts.
        AppCheck.setAppCheckProviderFactory(MarqueAppCheckProviderFactory())
        FirebaseApp.configure()
        AnalyticsService.configure()

        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        Firestore.firestore().settings = settings
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // FR-11.4 launch events. `.task` on the root view fires once
                    // per process, after the first render is scheduled, which is
                    // the closest proxy we have to "launch finished".
                    AnalyticsService.appOpened(isFirstOpen: LaunchState.consumeIsFirstOpen())
                    AnalyticsService.appLaunchCompleted(
                        durationMs: Int(Date().timeIntervalSince(launchStartedAt) * 1000)
                    )
                }
                .environmentObject(carStore)
                .environmentObject(authService)
                .environmentObject(exploreStore)
                .environmentObject(followStore)
                .environmentObject(subscriptionStore)
                .environmentObject(blockStore)
                .environmentObject(notificationStore)
                .environmentObject(chatStore)
                .environmentObject(scanAllowanceStore)
                .environmentObject(featureFlagsStore)
                .environmentObject(appDelegate)
                .onChange(of: authService.authState) { _, newState in
                    if case .authenticated(let user) = newState {
                        // FR-11.3: binds the anonymous pre-signup ID to the uid so
                        // the install -> signup funnel stays connected. Aliasing is
                        // idempotent past the first call (see AnalyticsService).
                        AnalyticsService.identify(uid: user.id)
                        // FR-11.8: ties crash reports to the reporting uid.
                        CrashReportingService.identify(uid: user.id)
                        carStore.startListening(userId: user.id)
                        exploreStore.startListening()
                        followStore.startListening(uid: user.id)
                        blockStore.startListening(uid: user.id)
                        notificationStore.startListening(uid: user.id)
                        chatStore.startListening(uid: user.id)
                        scanAllowanceStore.startListening(uid: user.id)
                        Task { await subscriptionStore.load() }
                    } else {
                        carStore.stopListening()
                        exploreStore.stopListening()
                        followStore.stopListening()
                        blockStore.stopListening()
                        notificationStore.stopListening()
                        chatStore.stopListening()
                        scanAllowanceStore.stopListening()
                        subscriptionStore.reset()
                        // Issues a fresh anonymous ID so the next person to sign in
                        // on this device isn't merged into the previous identity.
                        AnalyticsService.reset()
                        CrashReportingService.reset()
                    }
                }
                .onChange(of: subscriptionStore.isPro) { oldValue, newValue in
                    guard oldValue != newValue else { return }
                    // Only propagate after StoreKit has been queried for the current
                    // session — prevents a stale `isPro` from one user clobbering
                    // another user's Firestore doc on sign-in flip.
                    guard subscriptionStore.hasLoaded else { return }
                    authService.setProStatus(newValue)
                }
                // load() sets isPro (a @Published setter fires synchronously) before
                // its `defer { hasLoaded = true }` runs, so a device already
                // entitled at launch — a direct purchase StoreKit already knows
                // about, or Family Sharing — flips isPro to true while hasLoaded is
                // still false. The guard above then drops that flip, and nothing
                // else re-fires it: isPro doesn't change again this session, so
                // AppUser.isProMember (the Garage/Settings PRO badge) never gets
                // set, even though subscriptionStore.isPro is correctly true
                // everywhere else. Catch it up once loading actually finishes.
                .onChange(of: subscriptionStore.hasLoaded) { _, hasLoaded in
                    if hasLoaded { authService.setProStatus(subscriptionStore.isPro) }
                }
        }
    }
}

// MARK: - Root View

// Drives top-level navigation: Onboarding → Auth → Main App
private struct RootView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        Group {
            if !authService.hasSeenOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else if !authService.isAuthenticated {
                LoginView()
                    .transition(.opacity)
            } else if !authService.isEmailVerified {
                VerifyEmailView()
                    .transition(.opacity)
            } else if authService.isResolvingProfile {
                // Existing account, no local profile (reinstall / new device): hold
                // here while AuthService checks Firestore, so ProfileSetupView
                // doesn't flash for someone who has already set up their profile.
                ProfileResolvingView()
                    .transition(.opacity)
            } else if !authService.hasCompletedProfileSetup {
                ProfileSetupView()
                    .transition(.opacity)
            } else if authService.needsFirstCarStep {
                // FR-13.2/13.3 — the onboarding step ends at a saved car, not an
                // empty Garage screen. Reuses AddCarView (same VIN/manual form the
                // "+" tab sheet uses) in its onboarding context rather than
                // dismissing to a sheet.
                AddCarView(onboarding: .init(
                    onSkip: { authService.completeFirstCarStep(addedCar: false) },
                    onAdded: { authService.completeFirstCarStep(addedCar: true) }
                ))
                .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authService.hasSeenOnboarding)
        .animation(.easeInOut(duration: 0.25), value: authService.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: authService.isEmailVerified)
        .animation(.easeInOut(duration: 0.25), value: authService.isResolvingProfile)
        .animation(.easeInOut(duration: 0.25), value: authService.hasCompletedProfileSetup)
        .animation(.easeInOut(duration: 0.25), value: authService.needsFirstCarStep)
    }
}

// Brief holding screen while AuthService looks up an existing profile in Firestore.
private struct ProfileResolvingView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading your profile…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading your profile")
    }
}

// MARK: - Main Tab View

private struct MainTabView: View {
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var appDelegate: AppDelegate
    @EnvironmentObject var authService: AuthService

    @State private var selectedTab: Tab = .garage
    @State private var showingAddCar = false
    @State private var showingPaywall = false

    private enum Tab: Hashable { case garage, add, explore }

    private var atCarLimit: Bool {
        carStore.cars.count >= 3 && !subscriptionStore.isPro
    }

    // Intercept selection of the center "+" tab — trigger the add-car flow
    // instead of switching tabs.
    private var tabBinding: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .add {
                    if atCarLimit { showingPaywall = true }
                    else { showingAddCar = true }
                } else {
                    selectedTab = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if carStore.isOffline {
                offlineBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            TabView(selection: tabBinding) {
                CarListView()
                    .tabItem { Label("Garage", systemImage: "car.fill") }
                    .tag(Tab.garage)

                // Placeholder content — this tab is never actually selected.
                // The selection binding intercepts taps and opens AddCarView.
                Color.clear
                    .tabItem { Image(systemName: "plus.circle.fill") }
                    .tag(Tab.add)

                ExploreView()
                    .tabItem { Label("Explore", systemImage: "globe") }
                    .tag(Tab.explore)
            }
            .onAppear {
                // No permission prompt here: FR-04.1 / FR-13.6 require it to be
                // requested when the user first sets an expiry date (each expiry
                // toggle calls `requestPermission()`), not on first launch.
                NotificationManager.scheduleAll(
                    for: carStore.cars,
                    licenseExpiry: authService.currentUser?.driverLicenseExpiryDate
                )
            }
            .onChange(of: carStore.cars) { _, newCars in
                NotificationManager.scheduleAll(
                    for: newCars,
                    licenseExpiry: authService.currentUser?.driverLicenseExpiryDate
                )
            }
            .onChange(of: authService.currentUser?.driverLicenseExpiryDate) { _, _ in
                NotificationManager.scheduleAll(
                    for: carStore.cars,
                    licenseExpiry: authService.currentUser?.driverLicenseExpiryDate
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: carStore.isOffline)
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: appDelegate.pendingCarID) { _, carID in
            if carID != nil { selectedTab = .garage }
        }
        .sheet(isPresented: $showingAddCar) {
            AddCarView()
        }
        .sheet(isPresented: $showingPaywall) {
            ProUpgradeView(trigger: .carLimit)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.footnote)
            Text("No connection — showing cached data")
                .font(.footnote)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray))
    }
}
