import SwiftUI
import FirebaseCore
import FirebaseFirestore

@main
struct Marque_PrototypeApp: App {
    @StateObject private var carStore = CarStore()
    @StateObject private var authService = AuthService()
    @StateObject private var socialStore = SocialStore()
    @StateObject private var exploreStore = ExploreStore()
    @StateObject private var followStore = FollowStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var blockStore = BlockStore()
    @StateObject private var notificationStore = NotificationStore()

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
    @EnvironmentObject var socialStore: SocialStore
    @EnvironmentObject var notificationStore: NotificationStore

    var body: some View {
        VStack(spacing: 0) {
            if carStore.isOffline {
                offlineBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            TabView {
                CarListView()
                    .tabItem { Label("Garage", systemImage: "car.fill") }

                ExploreView()
                    .tabItem { Label("Explore", systemImage: "globe") }

                NotificationsInboxView()
                    .tabItem { Label("Notifications", systemImage: "bell.fill") }
                    .badge(notificationStore.unreadCount > 0 ? "\(notificationStore.unreadCount)" : nil)

                MyProfileView()
                    .tabItem { Label("Profile", systemImage: "person.fill") }

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .onAppear {
                NotificationManager.requestPermission()
                NotificationManager.scheduleAll(for: carStore.cars)
            }
            .onChange(of: carStore.cars) { _, newCars in
                NotificationManager.scheduleAll(for: newCars)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: carStore.isOffline)
        .ignoresSafeArea(edges: .bottom)
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
