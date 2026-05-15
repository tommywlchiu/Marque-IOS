import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var didSend = false

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                if didSend {
                    successState
                } else {
                    inputState
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - States

    private var inputState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)

                Text("Enter your email address and we'll send you a link to reset your password.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .submitLabel(.send)
                .onSubmit { if canSubmit { sendReset() } }

            MarquePrimaryButton("Send Reset Link", isLoading: authService.isLoading) {
                sendReset()
            }
            .disabled(!canSubmit)
        }
    }

    private var successState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.green)
            }

            VStack(spacing: 8) {
                Text("Check Your Email")
                    .font(.title2).fontWeight(.bold)
                Text("We sent a reset link to **\(email)**. Check your inbox and follow the instructions.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func sendReset() {
        Task {
            let success = await authService.resetPassword(email: email.trimmingCharacters(in: .whitespaces))
            if success { didSend = true }
        }
    }
}
