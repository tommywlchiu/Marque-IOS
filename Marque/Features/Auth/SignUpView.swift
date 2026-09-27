import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var showingForgotPassword = false

    /// Called with the typed email when the user picks "Sign in with password"
    /// on the collision card, before the sheet dismisses.
    var onSignInWithPassword: ((String) -> Void)? = nil
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
            ZStack {
                ShowroomBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        header

                        // Not else-if: tapping Apple on the collision card can itself fail
                        // (e.g. the existing account is password-based), and that message
                        // must show alongside the card rather than be hidden by it.
                        if let error = authService.errorMessage {
                            AuthErrorBanner(message: error)
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
                    .animation(.easeOut(duration: 0.25), value: authService.errorMessage)
                    .animation(.easeOut(duration: 0.25), value: authService.emailCollision)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // Scoped to this subtree (not `.preferredColorScheme`, which would
        // change the whole window) so the rest of the app is unaffected.
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView(prefillEmail: email)
        }
        .onChange(of: email) { _, _ in
            authService.clearEmailCollision()
        }
        .onChange(of: authService.errorMessage) { _, newValue in
            if newValue != nil { AuthHaptics.error() }
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
        VStack(spacing: 14) {
            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: 56)

            Text("Join the community of car enthusiasts.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func emailCollisionCard(_ collision: AuthService.EmailCollision) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("You already have an account")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("There's already a Marque account for \(collision.email). Sign in the way you did before.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                SocialSignInButton(icon: "apple.logo", label: "Continue with Apple", style: .apple) {
                    signInWithApple()
                }
                SocialSignInButton(icon: "g.circle.fill", label: "Continue with Google", style: .google) {
                    signInWithGoogle()
                }
            }

            VStack(spacing: 8) {
                Button("Sign in with password") {
                    onSignInWithPassword?(email.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Button("Forgot password?") { showingForgotPassword = true }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(.white.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var formSection: some View {
        VStack(spacing: 14) {
            fieldRow(icon: "person", isFocused: focusedField == .displayName) {
                TextField("Full Name", text: $displayName)
                    .textContentType(.name)
                    .focused($focusedField, equals: .displayName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .username }
            }

            fieldRow(icon: "at", isFocused: focusedField == .username) {
                TextField("Username (e.g. alexjdrives)", text: $username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }
            }

            fieldRow(icon: "envelope", isFocused: focusedField == .email) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }

            fieldRow(icon: "lock", isFocused: focusedField == .password, trailing: {
                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            }) {
                Group {
                    if isPasswordVisible {
                        TextField("Password (8+ characters)", text: $password)
                    } else {
                        SecureField("Password (8+ characters)", text: $password)
                    }
                }
                .textContentType(.newPassword)
                .focused($focusedField, equals: .password)
                .submitLabel(.next)
                .onSubmit { focusedField = .confirmPassword }
            }

            fieldRow(icon: "lock", isFocused: focusedField == .confirmPassword, trailing: {
                Button {
                    isConfirmPasswordVisible.toggle()
                } label: {
                    Image(systemName: isConfirmPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel(isConfirmPasswordVisible ? "Hide password" : "Show password")
            }) {
                Group {
                    if isConfirmPasswordVisible {
                        TextField("Confirm Password", text: $confirmPassword)
                    } else {
                        SecureField("Confirm Password", text: $confirmPassword)
                    }
                }
                .textContentType(.newPassword)
                .focused($focusedField, equals: .confirmPassword)
                .submitLabel(.go)
                .onSubmit {
                    if canSubmit { signUp() }
                }
            }

            if !passwordsMatch {
                Text("Passwords do not match.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeOut(duration: 0.2), value: focusedField)
    }

    /// One glass-chrome row: a leading SF Symbol, the field content, and an
    /// optional trailing accessory (the password show/hide toggle).
    private func fieldRow<Content: View, Trailing: View>(
        icon: String,
        isFocused: Bool,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 18)
            content()
                .foregroundStyle(.white)
            trailing()
        }
        .authFieldChrome(isFocused: isFocused)
    }

    private func fieldRow<Content: View>(
        icon: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        fieldRow(icon: icon, isFocused: isFocused, trailing: { EmptyView() }, content: content)
    }

    private var createButton: some View {
        AuthPrimaryButton(title: "Create Account", isLoading: authService.isLoading) {
            signUp()
        }
        .disabled(!canSubmit)
        .padding(.horizontal, 24)
    }

    private var termsFooter: some View {
        Text(legalText)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.4))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }

    private var legalText: AttributedString {
        var str = AttributedString("By creating an account you agree to our ")
        var tos = AttributedString("Terms of Service")
        tos.link = AppLinks.termsOfService
        tos.foregroundColor = .white.opacity(0.6)
        var mid = AttributedString(" and ")
        var pp = AttributedString("Privacy Policy")
        pp.link = AppLinks.privacyPolicy
        pp.foregroundColor = .white.opacity(0.6)
        return str + tos + mid + pp + AttributedString(".")
    }

    private func signUp() {
        AuthHaptics.tap()
        GarageEntranceCoordinator.shared.arm()
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
        GarageEntranceCoordinator.shared.arm()
        Task {
            await authService.signInWithApple()
            if authService.isAuthenticated { dismiss() }
        }
    }

    private func signInWithGoogle() {
        GarageEntranceCoordinator.shared.arm()
        Task {
            await authService.signInWithGoogle()
            if authService.isAuthenticated { dismiss() }
        }
    }
}
