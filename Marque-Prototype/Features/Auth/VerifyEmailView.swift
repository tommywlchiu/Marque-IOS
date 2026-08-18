import SwiftUI
import FirebaseAuth

struct VerifyEmailView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase

    @State private var isChecking = false
    @State private var isSending = false
    @State private var resendCooldown = 0
    @State private var didJustResend = false
    @State private var notYetVerified = false

    private var email: String {
        Auth.auth().currentUser?.email ?? ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer().frame(height: 12)

                header

                statusMessage

                actions

                Spacer()

                changeEmailFooter
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .navigationTitle("Verify Email")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                if resendCooldown > 0 { resendCooldown -= 1 }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await silentRecheck() } }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 8) {
                Text("Verify your email")
                    .font(.title2).fontWeight(.bold)
                Text(subtitleAttributed)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var subtitleAttributed: AttributedString {
        var prefix = AttributedString("We sent a link to ")
        var bold = AttributedString(email.isEmpty ? "your inbox" : email)
        bold.font = .subheadline.weight(.semibold)
        bold.foregroundColor = .primary
        let suffix = AttributedString(". Tap it, then come back to finish setting up your account.")
        return prefix + bold + suffix
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let error = authService.errorMessage {
            MarqueErrorBanner(message: error)
        } else if notYetVerified {
            inlineMessage(
                icon: "exclamationmark.circle.fill",
                color: .orange,
                text: "We don't see a verification yet. Try the link again, then tap I've Verified."
            )
        } else if didJustResend {
            inlineMessage(
                icon: "checkmark.circle.fill",
                color: .green,
                text: "Verification email resent. Check your inbox."
            )
        }
    }

    private func inlineMessage(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            MarquePrimaryButton("I've Verified", isLoading: isChecking) {
                Task { await check() }
            }

            Button(action: { Task { await resend() } }) {
                if isSending {
                    ProgressView()
                } else if resendCooldown > 0 {
                    Text("Resend Email in \(resendCooldown)s")
                } else {
                    Text("Resend Email")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(resendCooldown > 0 ? .secondary : .accentColor)
            .disabled(resendCooldown > 0 || isSending)
        }
    }

    private var changeEmailFooter: some View {
        VStack(spacing: 4) {
            Text("Wrong email?")
                .font(.footnote)
                .foregroundColor(.secondary)
            Button("Use a Different Email") {
                authService.signOut()
            }
            .font(.footnote.weight(.semibold))
        }
    }

    // MARK: - Actions

    private func check() async {
        isChecking = true
        notYetVerified = false
        didJustResend = false
        await authService.reloadEmailVerification()
        isChecking = false
        // If still not verified, surface a soft hint. The RootView transition
        // handles the success case automatically once isEmailVerified flips.
        if !authService.isEmailVerified { notYetVerified = true }
    }

    private func resend() async {
        isSending = true
        didJustResend = false
        notYetVerified = false
        let success = await authService.resendVerificationEmail()
        isSending = false
        if success {
            didJustResend = true
            resendCooldown = 60
        }
    }

    // Quiet check used on foreground — no error UI if it still isn't verified,
    // because the user didn't ask. RootView transitions if the state flips.
    private func silentRecheck() async {
        await authService.reloadEmailVerification()
    }
}
