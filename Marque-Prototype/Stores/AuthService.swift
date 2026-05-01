import Foundation

enum AuthState: Equatable {
    case unauthenticated
    case authenticated(AppUser)
}

import FirebaseAuth
import AuthenticationServices
import CryptoKit
import UIKit

@MainActor
class AuthService: NSObject, ObservableObject {
    @Published var authState: AuthState = .unauthenticated
    @Published var hasSeenOnboarding: Bool
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let onboardingKey = "marque_has_seen_onboarding"
    private var stateListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    private var appleCompletion: CheckedContinuation<Void, Error>?
    private var appleSignInController: ASAuthorizationController?

    override init() {
        hasSeenOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        super.init()

        stateListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let fu = firebaseUser {
                    let p = LocalProfile.load(uid: fu.uid)
                    self.authState = .authenticated(AppUser(firebaseUser: fu, profile: (username: p.username, bio: p.bio, location: p.location)))
                } else {
                    self.authState = .unauthenticated
                }
            }
        }
    }

    deinit {
        if let stateListener { Auth.auth().removeStateDidChangeListener(stateListener) }
    }

    var currentUser: AppUser? {
        guard case .authenticated(let user) = authState else { return nil }
        return user
    }

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
        hasSeenOnboarding = true
    }

    // MARK: - Email / Password

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = authErrorMessage(from: error)
        }
    }

    func signUp(displayName: String, username: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName.trimmingCharacters(in: .whitespaces)
            try await changeRequest.commitChanges()

            let resolved = username.trimmingCharacters(in: .whitespaces).isEmpty
                ? (email.components(separatedBy: "@").first ?? "")
                : username.trimmingCharacters(in: .whitespaces)
            LocalProfile(username: resolved, bio: "", location: "").save(uid: result.user.uid)
        } catch {
            errorMessage = authErrorMessage(from: error)
        }
    }

    // MARK: - Apple Sign In

    func signInWithApple() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await performAppleSignIn()
        } catch {
            let asError = error as? ASAuthorizationError
            if asError?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performAppleSignIn() async throws {
        let nonce = randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.appleCompletion = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.appleSignInController = controller
            controller.performRequests()
        }
    }

    // MARK: - Google Sign In
    // TODO: Add GoogleSignIn SDK via Xcode → File → Add Package Dependencies
    // URL: https://github.com/google/GoogleSignIn-iOS  Product: GoogleSignIn
    // Then replace this stub — see inline comments for the implementation.

    func signInWithGoogle() async {
        errorMessage = "Google Sign In setup required — see AuthService.swift TODO."
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            return true
        } catch {
            errorMessage = authErrorMessage(from: error)
            return false
        }
    }

    // MARK: - Profile Update

    func updateProfile(displayName: String, username: String, bio: String, location: String) {
        guard case .authenticated(var user) = authState,
              let firebaseUser = Auth.auth().currentUser else { return }

        let changeRequest = firebaseUser.createProfileChangeRequest()
        changeRequest.displayName = displayName
        changeRequest.commitChanges(completion: nil)

        LocalProfile(username: username, bio: bio, location: location).save(uid: firebaseUser.uid)

        user.displayName = displayName
        user.username = username
        user.bio = bio
        user.location = location
        authState = .authenticated(user)
    }

    // MARK: - Sign Out

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: - Helpers

    private func authErrorMessage(from error: Error) -> String {
        let code = AuthErrorCode(_bridgedNSError: error as NSError)
        switch code {
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .emailAlreadyInUse:
            return "An account with this email already exists."
        case .weakPassword:
            return "Password must be at least 8 characters."
        case .userNotFound:
            return "No account found with this email."
        case .networkError:
            return "Network error. Please check your connection."
        default:
            return error.localizedDescription
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { byte in charset[Int(byte) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let idTokenData = credential.identityToken,
            let idToken = String(data: idTokenData, encoding: .utf8)
        else {
            Task { @MainActor in self.appleCompletion?.resume(throwing: URLError(.badServerResponse)) }
            return
        }

        Task {
            do {
                let firebaseCredential = OAuthProvider.appleCredential(
                    withIDToken: idToken,
                    rawNonce: await self.currentNonce,
                    fullName: credential.fullName
                )
                try await Auth.auth().signIn(with: firebaseCredential)
                await MainActor.run {
                    self.appleSignInController = nil
                    self.appleCompletion?.resume()
                }
            } catch {
                await MainActor.run {
                    self.appleSignInController = nil
                    self.appleCompletion?.resume(throwing: error)
                }
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.appleSignInController = nil
            self.appleCompletion?.resume(throwing: error)
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            .flatMap { $0.keyWindow } ?? UIWindow()
    }
}

// MARK: - LocalProfile
// Stores fields Firebase Auth doesn't natively carry (username, bio, location).
// Replace with a Firestore document in production.

private struct LocalProfile: Codable {
    var username: String
    var bio: String
    var location: String

    static func load(uid: String) -> LocalProfile {
        guard
            let data = UserDefaults.standard.data(forKey: "marque_profile_\(uid)"),
            let profile = try? JSONDecoder().decode(LocalProfile.self, from: data)
        else {
            return LocalProfile(username: "", bio: "", location: "")
        }
        return profile
    }

    func save(uid: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "marque_profile_\(uid)")
        }
    }
}

