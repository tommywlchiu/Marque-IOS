import SwiftUI
import FirebaseAppCheck
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import FirebaseFunctions

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
    @StateObject private var likeStore = LikeStore()
    @StateObject private var commentStore = CommentStore()
    @StateObject private var pushStore = PushStore()

    init() {
        _ = launchStartedAt  // force the global's lazy init as early as possible
        // Must precede configure(): App Check reads the factory when Firebase starts.
        AppCheck.setAppCheckProviderFactory(MarqueAppCheckProviderFactory())
        FirebaseApp.configure()
        AnalyticsService.configure()

        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        #if DEBUG
        // Launch with `-use_firebase_emulators YES` to run against the local
        // Firebase Emulator Suite (`firebase emulators:start`) instead of
        // production. Compiled out of Release. Memory cache so emulator data
        // never mixes with the production offline cache on this device.
        if UserDefaults.standard.bool(forKey: "use_firebase_emulators") {
            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            settings.host = "127.0.0.1:8080"
            settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            Storage.storage().useEmulator(withHost: "127.0.0.1", port: 9199)
            Functions.functions().useEmulator(withHost: "127.0.0.1", port: 5001)
        }
        #endif
        Firestore.firestore().settings = settings
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    // The widget's deep link: marque://car/<uuid>. Reuses the
                    // same pendingCarID path a like/comment push already uses —
                    // GarageHomeView.tryDeepLinkNavigation() picks it up.
                    guard url.scheme == "marque", url.host == "car",
                          let id = UUID(uuidString: url.lastPathComponent) else { return }
                    appDelegate.pendingCarID = id
                }
                .task {
                    // FR-11.4 launch events. `.task` on the root view fires once
                    // per process, after the first render is scheduled, which is
                    // the closest proxy we have to "launch finished".
                    AnalyticsService.appOpened(isFirstOpen: LaunchState.consumeIsFirstOpen())
                    AnalyticsService.appLaunchCompleted(
                        durationMs: Int(Date().timeIntervalSince(launchStartedAt) * 1000)
                    )
                    // Cross-store hook: the FCM token doc must be deleted while
                    // the outgoing user is still signed in, i.e. before
                    // AuthService.signOut() calls Auth.signOut(). The
                    // authState observer below runs too late for that.
                    authService.willSignOut = { [pushStore] in await pushStore.prepareForSignOut() }
                    // CarStore's local persistence cache can already have the
                    // right value by the time this view mounts, so onChange
                    // below (which only fires on an actual change) may never
                    // fire this session — same reason MainTabView's own
                    // onChange(of: carStore.cars) is paired with an onAppear.
                    WidgetSnapshotService.sync(cars: carStore.cars)
                    BodyStyleBackfill.run(carStore: carStore)
                    RangeBackfill.run(carStore: carStore)
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
                .environmentObject(likeStore)
                .environmentObject(commentStore)
                .environmentObject(pushStore)
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
                        likeStore.startListening(uid: user.id)
                        commentStore.startListening(uid: user.id)
                        pushStore.startListening(uid: user.id)
                        Task { await subscriptionStore.load() }
                    } else {
                        carStore.stopListening()
                        exploreStore.stopListening()
                        followStore.stopListening()
                        blockStore.stopListening()
                        notificationStore.stopListening()
                        chatStore.stopListening()
                        scanAllowanceStore.stopListening()
                        likeStore.stopListening()
                        commentStore.stopListening()
                        pushStore.stopListening()
                        subscriptionStore.reset()
                        // Issues a fresh anonymous ID so the next person to sign in
                        // on this device isn't merged into the previous identity.
                        AnalyticsService.reset()
                        CrashReportingService.reset()
                        // A signed-out device's widget must not keep showing the
                        // previous account's cars.
                        WidgetSnapshotService.sync(cars: [])
                    }
                }
                .onChange(of: carStore.cars) { _, cars in
                    WidgetSnapshotService.sync(cars: cars)
                    BodyStyleBackfill.run(carStore: carStore)
                    RangeBackfill.run(carStore: carStore)
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
                // Cross-store coordination for full blocking: BlockStore
                // doesn't know about FollowStore (stores stay decoupled), so
                // this app-root observer bridges the two. The server-side
                // cascade (onUserBlocked trigger) deletes the actual
                // Firestore follow edges; this just makes this device's UI
                // reflect the unfollow immediately instead of waiting on it.
                // A brand-new account's first token registration is denied until
                // its users/{uid} profile doc exists (the devices rule requires
                // it, so a deleted account's live token can't write). Profile
                // setup creates that doc, so register again once it's done.
                .onChange(of: authService.hasCompletedProfileSetup) { _, done in
                    if done { pushStore.refreshRegistration() }
                }
                .onChange(of: blockStore.lastBlockedUID) { _, uid in
                    if let uid { followStore.removeLocal(uid: uid) }
                }
        }
    }
}

// MARK: - Root View

// Drives top-level navigation: Onboarding → Auth → Main App
private struct RootView: View {
    @EnvironmentObject var authService: AuthService
    // Observes the shared arm/consume flag set by LoginView/SignUpView on an
    // active sign-in/sign-up tap this session (never inferred from
    // `isAuthenticated`, which also flips on a cold-launch session restore).
    @StateObject private var entrance = GarageEntranceCoordinator.shared
    @State private var showEntranceAnimation = false
    /// New per sign-in, and used as MainTabView's identity, so each signed-in
    /// session starts on a fresh Garage root. Without it, signing out from
    /// Settings and back in (as the same or a different account) reopened on
    /// Settings: SwiftUI carried the tab/navigation state across the sign-out.
    @State private var sessionID = UUID()

    /// True when the routing below lands on MainTabView (the final else).
    private var isShowingGarage: Bool {
        authService.hasSeenOnboarding && authService.isAuthenticated && authService.isEmailVerified
            && !authService.isResolvingProfile && authService.hasCompletedProfileSetup
            && !authService.needsFirstCarStep
    }

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
                // The user may have passed through VerifyEmail, profile setup or
                // the first-car step since arming the entrance; only the first
                // appearance of the garage itself consumes the arm and plays it.
                MainTabView()
                    .id(sessionID)
                    .transition(.opacity)
                    .onAppear {
                        if entrance.consumeIfArmed() {
                            showEntranceAnimation = true
                        }
                    }
            }
        }
        // Outside the Group so the door isn't caught in the branch's opacity
        // cross-fade (it must be solid from the first frame, not fade in with
        // the garage). `entrance.isArmed` covers the frames before onAppear has
        // consumed the arm, so the garage never flashes before the door.
        .overlay {
            if isShowingGarage && (entrance.isArmed || showEntranceAnimation) {
                GarageEntranceView {
                    showEntranceAnimation = false
                }
                .transition(.identity)
            }
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated { sessionID = UUID() }
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

/// The main tabs. Exposed so a screen can jump to another tab through
/// `\.selectMainTab` (the Garage's document alerts open Wallet).
enum MainTab: Hashable { case garage, explore, photos, wallet }

private struct SelectMainTabKey: EnvironmentKey {
    static let defaultValue: (MainTab) -> Void = { _ in }
}

extension EnvironmentValues {
    var selectMainTab: (MainTab) -> Void {
        get { self[SelectMainTabKey.self] }
        set { self[SelectMainTabKey.self] = newValue }
    }
}

private struct MainTabView: View {
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var appDelegate: AppDelegate
    @EnvironmentObject var authService: AuthService

    @State private var selectedTab: MainTab = .garage
    @State private var showingPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            if carStore.isOffline {
                offlineBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            TabView(selection: $selectedTab) {
                GarageHomeView()
                    .tabItem { Label("Garage", systemImage: "car.fill") }
                    .tag(MainTab.garage)

                ExploreView()
                    .tabItem { Label("Explore", systemImage: "globe") }
                    .tag(MainTab.explore)

                PhotosTabView()
                    .modifier(FollowPushRouter())
                    .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
                    .tag(MainTab.photos)

                WalletView()
                    .modifier(FollowPushRouter())
                    .tabItem { Label("Wallet", systemImage: "wallet.pass") }
                    .tag(MainTab.wallet)
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
        .environment(\.selectMainTab) { selectedTab = $0 }
        .sheet(isPresented: $showingPaywall) {
            ProUpgradeView(trigger: .carLimit)
        }
        // The server enforces the free car limit (FR-08.8). A car the client let
        // through, e.g. because the device thinks it's Pro while the server
        // doesn't, is rolled back by CarStore; tell the user why it vanished.
        .alert("Car limit reached", isPresented: Binding(
            get: { carStore.carLimitRejected },
            set: { if !$0 { carStore.clearCarLimitRejected() } }
        )) {
            Button("See Marque Pro") {
                carStore.clearCarLimitRejected()
                showingPaywall = true
            }
            Button("OK", role: .cancel) { carStore.clearCarLimitRejected() }
        } message: {
            Text("Free accounts can have up to \(CarStore.freeCarLimit) cars, so your new car wasn't saved. Upgrade to Marque Pro for unlimited cars.")
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
