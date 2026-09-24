import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var showingSignUp = false
    @State private var showingForgotPassword = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    header
                    formFields
                    signInButton
                    dividerSection
                    socialButtons
                    signUpPrompt
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingSignUp) {
            SignUpView()
        }
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView()
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
            Image(systemName: "car.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Marque")
                .font(.largeTitle).fontWeight(.bold)

            Text("Sign in to your garage")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var formFields: some View {
        VStack(spacing: 14) {
            if let error = authService.errorMessage {
                MarqueErrorBanner(message: error)
            }

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .email)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .submitLabel(.go)
                .onSubmit {
                    if canSubmit { Task { await authService.signIn(email: email, password: password) } }
                }

            HStack {
                Spacer()
                Button("Forgot password?") { showingForgotPassword = true }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
            }
        }
    }

    private var signInButton: some View {
        MarquePrimaryButton("Sign In", isLoading: authService.isLoading) {
            Task { await authService.signIn(email: email, password: password) }
        }
        .disabled(!canSubmit)
    }

    private var dividerSection: some View {
        LabeledDivider(label: "or continue with")
    }

    private var socialButtons: some View {
        VStack(spacing: 12) {
            SocialSignInButton(icon: "apple.logo", label: "Continue with Apple") {
                Task { await authService.signInWithApple() }
            }
            SocialSignInButton(icon: "g.circle.fill", label: "Continue with Google") {
                Task { await authService.signInWithGoogle() }
            }
        }
    }

    private var signUpPrompt: some View {
        HStack(spacing: 4) {
            Text("Don't have an account?")
                .foregroundColor(.secondary)
            Button("Sign up") { showingSignUp = true }
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}
