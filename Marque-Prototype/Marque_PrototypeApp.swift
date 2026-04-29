import SwiftUI
import FirebaseCore

@main
struct Marque_PrototypeApp: App {
    @StateObject private var carStore = CarStore()
    @StateObject private var authService = AuthService()
    @StateObject private var socialStore = SocialStore()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(carStore)
                .environmentObject(authService)
                .environmentObject(socialStore)
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
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authService.hasSeenOnboarding)
        .animation(.easeInOut(duration: 0.25), value: authService.isAuthenticated)
    }
}

// MARK: - Main Tab View

private struct MainTabView: View {
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var socialStore: SocialStore

    var body: some View {
        TabView {
            CarListView()
                .tabItem { Label("Garage", systemImage: "car.fill") }

            ExploreView()
                .tabItem { Label("Explore", systemImage: "globe") }

            NotificationsInboxView()
                .tabItem { Label("Notifications", systemImage: "bell.fill") }
                .badge(socialStore.unreadCount > 0 ? "\(socialStore.unreadCount)" : nil)

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
}
