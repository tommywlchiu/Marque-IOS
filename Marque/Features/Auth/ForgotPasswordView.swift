import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var email: String
    @State private var didSend = false
    @FocusState private var emailFocused: Bool

    /// `prefillEmail` is whatever the presenting screen already has typed, so
    /// the user doesn't enter the same address twice.
    init(prefillEmail: String = "") {
        _email = State(initialValue: prefillEmail.trimmingCharacters(in: .whitespaces))
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ShowroomBackground()

                ScrollView {
                    VStack(spacing: 28) {
                        if didSend {
                            successState
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        } else {
                            inputState
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 40)
                    .animation(.easeOut(duration: 0.3), value: didSend)
                    .animation(.easeOut(duration: 0.25), value: authService.errorMessage)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // Same scoped dark look as Login / Sign Up, which present this sheet.
        .environment(\.colorScheme, .dark)
        .onChange(of: authService.errorMessage) { _, newValue in
            if newValue != nil { AuthHaptics.error() }
        }
        .onAppear {
            // Clears any sign-in error left over from the presenting screen.
            authService.errorMessage = nil
            // Nothing to type when the email came prefilled; go straight to Send.
            if email.isEmpty { emailFocused = true }
        }
    }

    // MARK: - States

    private var inputState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                Image(systemName: "key.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))

                Text("Enter your email and we'll send you a link to reset your password.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            if let error = authService.errorMessage {
                AuthErrorBanner(message: error)
            }

            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 18)
                TextField("Email", text: $email, prompt: Text("Email").foregroundStyle(.white.opacity(0.35)))
                    .foregroundStyle(.white)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($emailFocused)
                    .submitLabel(.send)
                    .onSubmit { if canSubmit { sendReset() } }
            }
            .authFieldChrome(isFocused: emailFocused)

            AuthPrimaryButton(title: "Send Reset Link", isLoading: authService.isLoading) {
                AuthHaptics.tap()
                sendReset()
            }
            .disabled(!canSubmit)
        }
    }

    private var successState: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 88, height: 88)
                .background(Circle().fill(Color.green.opacity(0.14)))
                .overlay(Circle().strokeBorder(Color.green.opacity(0.35), lineWidth: 1))

            VStack(spacing: 8) {
                Text("Check Your Email")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("We sent a reset link to **\(email)**. Check your inbox and follow the instructions.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            AuthPrimaryButton(title: "Done", isLoading: false) { dismiss() }
                .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func sendReset() {
        Task {
            let success = await authService.resetPassword(email: email.trimmingCharacters(in: .whitespaces))
            if success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                didSend = true
            }
        }
    }
}
