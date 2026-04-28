import Foundation

enum AuthState: Equatable {
    case unauthenticated
    case authenticated(AppUser)
}

// Mock auth service — replace internals with Firebase Auth when ready.
@MainActor
class AuthService: ObservableObject {
    @Published var authState: AuthState = .unauthenticated
    @Published var hasSeenOnboarding: Bool
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let onboardingKey = "marque_has_seen_onboarding"

    init() {
        hasSeenOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }

    var currentUser: AppUser? {
        guard case .authenticated(let user) = authState else { return nil }
        return user
    }

    var isAuthenticated: Bool {
        guard case .authenticated = authState else { return false }
        return true
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
        hasSeenOnboarding = true
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // Simulate network latency
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }
        authState = .authenticated(.preview)
    }

    func signInWithApple() async {
        isLoading = true
        defer { isLoading = false }
        try? await Task.sleep(nanoseconds: 500_000_000)
        authState = .authenticated(.preview)
    }

    func signInWithGoogle() async {
        isLoading = true
        defer { isLoading = false }
        try? await Task.sleep(nanoseconds: 500_000_000)
        authState = .authenticated(.preview)
    }

    func signUp(displayName: String, username: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !displayName.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill out all required fields."
            return
        }
        var user = AppUser.preview
        user.displayName = displayName
        user.username = username.isEmpty ? displayName.lowercased().replacingOccurrences(of: " ", with: "") : username
        authState = .authenticated(user)
    }

    func resetPassword(email: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        try? await Task.sleep(nanoseconds: 800_000_000)
        return !email.isEmpty
    }

    func updateProfile(displayName: String, username: String, bio: String, location: String) {
        guard case .authenticated(var user) = authState else { return }
        user.displayName = displayName
        user.username = username
        user.bio = bio
        user.location = location
        authState = .authenticated(user)
    }

    func signOut() {
        authState = .unauthenticated
    }
}
