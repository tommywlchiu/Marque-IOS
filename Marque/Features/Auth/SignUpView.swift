import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingForgotPassword = false
    @FocusState private var focusedField: Field?

    private enum Field { case displayName, username, email, password, confirmPassword }

    private var passwordsMatch: Bool { password == confirmPassword || confirmPassword.isEmpty }
    private var canSubmit: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 8 &&
        password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    // Not else-if: tapping Apple on the collision card can itself fail
                    // (e.g. the existing account is password-based), and that message
                    // must show alongside the card rather than be hidden by it.
                    if let error = authService.errorMessage {
                        MarqueErrorBanner(message: error)
                            .padding(.horizontal, 24)
                    }

                    if let collision = authService.emailCollision {
                        emailCollisionCard(collision)
                            .padding(.horizontal, 24)
                    }

                    formSection

                    createButton

                    termsFooter
                }
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView()
        }
        .onChange(of: email) { _, _ in
            authService.clearEmailCollision()
        }
        // Covers every way out of this sheet (swipe-down, Cancel, "Sign in with
        // password"), so the typed password never outlives the signup screen.
        // Skipped when leaving because sign-in just succeeded: AuthService may
        // still be about to link that password, and clears it itself afterward.
        .onDisappear {
            if !authService.isAuthenticated {
                authService.clearEmailCollision()
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        Text("Join the community of car enthusiasts.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }

    private func emailCollisionCard(_ collision: AuthService.EmailCollision) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("You already have an account")
                    .font(.headline)
                Text("There's already a Marque account for \(collision.email). Sign in the way you did before.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                SocialSignInButton(icon: "apple.logo", label: "Continue with Apple") {
                    signInWithApple()
                }
                SocialSignInButton(icon: "g.circle.fill", label: "Continue with Google") {
                    signInWithGoogle()
                }
            }

            VStack(spacing: 8) {
                Button("Sign in with password") { dismiss() }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Button("Forgot password?") { showingForgotPassword = true }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var formSection: some View {
        VStack(spacing: 14) {
            Group {
                TextField("Full Name", text: $displayName)
                    .textContentType(.name)
                    .focused($focusedField, equals: .displayName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .username }

                TextField("Username (e.g. alexjdrives)", text: $username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                SecureField("Password (8+ characters)", text: $password)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirmPassword }

                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirmPassword)
                    .submitLabel(.go)
                    .onSubmit {
                        if canSubmit { signUp() }
                    }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !passwordsMatch {
                Text("Passwords do not match.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 24)
    }

    private var createButton: some View {
        MarquePrimaryButton("Create Account", isLoading: authService.isLoading) {
            signUp()
        }
        .disabled(!canSubmit)
        .padding(.horizontal, 24)
    }

    private var termsFooter: some View {
        Text(legalText)
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }

    private var legalText: AttributedString {
        var str = AttributedString("By creating an account you agree to our ")
        var tos = AttributedString("Terms of Service")
        tos.link = AppLinks.termsOfService
        tos.foregroundColor = .accentColor
        var mid = AttributedString(" and ")
        var pp = AttributedString("Privacy Policy")
        pp.link = AppLinks.privacyPolicy
        pp.foregroundColor = .accentColor
        return str + tos + mid + pp + AttributedString(".")
    }

    private func signUp() {
        Task {
            await authService.signUp(
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                username: username.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            if authService.isAuthenticated { dismiss() }
        }
    }

    private func signInWithApple() {
        Task {
            await authService.signInWithApple()
            if authService.isAuthenticated { dismiss() }
        }
    }

    private func signInWithGoogle() {
        Task {
            await authService.signInWithGoogle()
            if authService.isAuthenticated { dismiss() }
        }
    }
}
