import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var showingSignUp = false
    @State private var showingForgotPassword = false
    @State private var headerAppeared = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ShowroomBackground()

                ScrollView {
                    VStack(spacing: 28) {
                        header
                        formFields
                            .staggeredAppear(1)
                        signInButton
                            .staggeredAppear(2)
                        dividerSection
                            .staggeredAppear(3)
                        socialButtons
                            .staggeredAppear(4)
                        signUpPrompt
                            .staggeredAppear(5)
                        footer
                            .staggeredAppear(5)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
        }
        // Scoped to this subtree (not `.preferredColorScheme`, which would
        // change the whole window) so the rest of the app is unaffected.
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showingSignUp) {
            // The collision card's "Sign in with password" hands back the
            // email already typed, so it doesn't have to be entered again.
            SignUpView(onSignInWithPassword: { typedEmail in
                email = typedEmail
                password = ""
                focusedField = .password
            })
        }
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView(prefillEmail: email)
        }
        .onChange(of: authService.errorMessage) { _, newValue in
            if newValue != nil { AuthHaptics.error() }
        }
        .onAppear {
            // Gated on isFreshOnboarding: this view is also reached by any
            // returning user who's simply signed out, which is not an
            // onboarding funnel step (see AuthService.isFreshOnboarding).
            if authService.isFreshOnboarding {
                AnalyticsService.onboardingStepViewed(step: .authentication)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 10) {
            LogoMarkWithShine()
                .frame(width: 120)

            Text("MARQUE")
                .font(.system(size: 20, weight: .semibold))
                .tracking(7)
                .foregroundStyle(.white.opacity(0.9))

            Text("Sign in to your garage")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
        }
        .opacity(headerAppeared ? 1 : 0)
        .scaleEffect(headerAppeared || reduceMotion ? 1 : 0.92)
        .blur(radius: headerAppeared || reduceMotion ? 0 : 8)
        .onAppear {
            let animation: Animation = reduceMotion
                ? .easeOut(duration: 0.3)
                : .spring(response: 0.7, dampingFraction: 0.75)
            withAnimation(animation) { headerAppeared = true }
        }
    }

    private var formFields: some View {
        VStack(spacing: 14) {
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
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }
            .authFieldChrome(isFocused: focusedField == .email)

            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 18)
                Group {
                    if isPasswordVisible {
                        TextField("Password", text: $password, prompt: Text("Password").foregroundStyle(.white.opacity(0.35)))
                    } else {
                        SecureField("Password", text: $password, prompt: Text("Password").foregroundStyle(.white.opacity(0.35)))
                    }
                }
                .foregroundStyle(.white)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    if canSubmit { submitSignIn() }
                }

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            }
            .authFieldChrome(isFocused: focusedField == .password)

            HStack {
                Spacer()
                Button("Forgot password?") { showingForgotPassword = true }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .animation(.easeOut(duration: 0.25), value: authService.errorMessage)
    }

    private var signInButton: some View {
        AuthPrimaryButton(title: "Sign In", isLoading: authService.isLoading) {
            submitSignIn()
        }
        .disabled(!canSubmit)
    }

    private var dividerSection: some View {
        LabeledDivider(label: "or continue with")
    }

    private var socialButtons: some View {
        VStack(spacing: 12) {
            SocialSignInButton(icon: "apple.logo", label: "Continue with Apple", style: .apple) {
                GarageEntranceCoordinator.shared.arm()
                Task { await authService.signInWithApple() }
            }
            SocialSignInButton(icon: "g.circle.fill", label: "Continue with Google", style: .google) {
                GarageEntranceCoordinator.shared.arm()
                Task { await authService.signInWithGoogle() }
            }
        }
    }

    private var signUpPrompt: some View {
        HStack(spacing: 4) {
            Text("Don't have an account?")
                .foregroundStyle(.white.opacity(0.55))
            Button("Sign up") { showingSignUp = true }
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .font(.subheadline)
    }

    private var footer: some View {
        Text(legalText)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.4))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }

    private var legalText: AttributedString {
        var str = AttributedString("By continuing you agree to our ")
        var tos = AttributedString("Terms of Service")
        tos.link = AppLinks.termsOfService
        tos.foregroundColor = .white.opacity(0.6)
        var mid = AttributedString(" and ")
        var pp = AttributedString("Privacy Policy")
        pp.link = AppLinks.privacyPolicy
        pp.foregroundColor = .white.opacity(0.6)
        return str + tos + mid + pp + AttributedString(".")
    }

    // MARK: - Actions

    private func submitSignIn() {
        AuthHaptics.tap()
        GarageEntranceCoordinator.shared.arm()
        Task { await authService.signIn(email: email, password: password) }
    }
}
