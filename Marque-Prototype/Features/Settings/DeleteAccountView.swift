import SwiftUI
import AuthenticationServices
import FirebaseAuth

struct DeleteAccountView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var password = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @FocusState private var passwordFocused: Bool

    private var provider: String { authService.signInProvider }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    warningHeader
                    if let error = errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    reauthSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isProcessing)
                }
            }
            // Belt-and-suspenders: dismiss the sheet the moment the auth state
            // transitions to unauthenticated, regardless of async task timing.
            .onChange(of: authService.authState) { _, newState in
                if case .unauthenticated = newState { dismiss() }
            }
        }
    }

    // MARK: - Warning

    private var warningHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundColor(.red)

            VStack(spacing: 8) {
                Text("This cannot be undone")
                    .font(.title3).fontWeight(.bold)
                Text("Deleting your account permanently removes all your cars, service history, photos, followers, and public profile. Your data cannot be recovered.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Re-auth section

    @ViewBuilder
    private var reauthSection: some View {
        switch provider {
        case "password":
            emailReauthSection
        case "apple.com":
            providerReauthSection(name: "Apple")
        default:
            providerReauthSection(name: "Google")
        }
    }

    private var emailReauthSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm your password to continue")
                    .font(.subheadline).fontWeight(.semibold)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($passwordFocused)
                    .padding(14)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            deleteButton(label: "Delete My Account") {
                Task { await deleteWithEmail() }
            }
            .disabled(password.isEmpty || isProcessing)
        }
        .onAppear { passwordFocused = true }
    }

    private func providerReauthSection(name: String) -> some View {
        VStack(spacing: 12) {
            Text("You'll be asked to verify your \(name) identity before your account is deleted.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            deleteButton(label: "Verify with \(name) & Delete") {
                Task { await deleteWithProvider() }
            }
        }
    }

    private func deleteButton(label: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Group {
                if isProcessing {
                    ProgressView().tint(.white)
                } else {
                    Text(label).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(isProcessing)
    }

    // MARK: - Delete flows

    private func deleteWithEmail() async {
        guard !password.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }
        errorMessage = nil
        do {
            try await authService.reauthenticate(password: password)
            try await authService.deleteAccount()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    private func deleteWithProvider() async {
        isProcessing = true
        defer { isProcessing = false }
        errorMessage = nil
        do {
            if provider == "apple.com" {
                try await authService.reauthenticateWithApple()
            } else {
                try await authService.reauthenticateWithGoogle()
            }
            try await authService.deleteAccount()
        } catch let error as NSError
            where error.domain == ASAuthorizationError.errorDomain
               && error.code == ASAuthorizationError.canceled.rawValue {
            // User cancelled the Apple sheet — no error shown.
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain {
            switch AuthErrorCode(rawValue: nsError.code) {
            case .wrongPassword:
                return "Incorrect password. Please try again."
            case .tooManyRequests:
                return "Too many attempts. Please try again later."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
