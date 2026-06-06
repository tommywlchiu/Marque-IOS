import SwiftUI
import FirebaseCore
import FirebaseFirestore

@main
struct Marque_PrototypeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var carStore = CarStore()
    @StateObject private var authService = AuthService()
    @StateObject private var socialStore = SocialStore()
    @StateObject private var exploreStore = ExploreStore()
    @StateObject private var followStore = FollowStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var blockStore = BlockStore()
    @StateObject private var notificationStore = NotificationStore()
    @StateObject private var smartcarStore = SmartcarStore()

    init() {
        FirebaseApp.configure()

        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        Firestore.firestore().settings = settings
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(carStore)
                .environmentObject(authService)
                .environmentObject(socialStore)
                .environmentObject(exploreStore)
                .environmentObject(followStore)
                .environmentObject(subscriptionStore)
                .environmentObject(blockStore)
                .environmentObject(notificationStore)
                .environmentObject(smartcarStore)
                .environmentObject(appDelegate)
                .onOpenURL { url in
                    // Smartcar Connect redirects back to marque://smartcar-callback.
                    // Phase 2 will fill in handleCallback; for now this just ignores.
                    _ = smartcarStore.handleCallback(url)
                }
                .onChange(of: authService.authState) { _, newState in
                    if case .authenticated(let user) = newState {
                        carStore.startListening(userId: user.id)
                        exploreStore.startListening()
                        followStore.startListening(uid: user.id)
                        blockStore.startListening(uid: user.id)
                        notificationStore.startListening(uid: user.id)
                        Task { await subscriptionStore.load() }
                    } else {
                        carStore.stopListening()
                        exploreStore.stopListening()
                        followStore.stopListening()
                        blockStore.stopListening()
                        notificationStore.stopListening()
                        subscriptionStore.reset()
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
            } else if !authService.hasCompletedProfileSetup {
                ProfileSetupView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authService.hasSeenOnboarding)
        .animation(.easeInOut(duration: 0.25), value: authService.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: authService.hasCompletedProfileSetup)
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
                NotificationManager.requestPermission()
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
            ProUpgradeView()
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
