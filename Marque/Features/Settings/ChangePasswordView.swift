import SwiftUI
import FirebaseAuth

struct ChangePasswordView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var didSucceed = false
    @FocusState private var focusedField: Field?

    private enum Field { case current, new, confirm }

    private var validationError: String? {
        guard newPassword.count >= 6 else {
            return "New password must be at least 6 characters."
        }
        guard newPassword == confirmPassword else {
            return "New password and confirmation don't match."
        }
        return nil
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty && validationError == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if didSucceed {
                        successState
                    } else {
                        formFields
                        submitButton
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isProcessing)
                }
            }
        }
    }

    // MARK: - Form

    private var formFields: some View {
        VStack(spacing: 14) {
            if let errorMessage {
                MarqueErrorBanner(message: errorMessage)
            }

            SecureField("Current password", text: $currentPassword)
                .textContentType(.password)
                .focused($focusedField, equals: .current)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .submitLabel(.next)
                .onSubmit { focusedField = .new }

            SecureField("New password", text: $newPassword)
                .textContentType(.newPassword)
                .focused($focusedField, equals: .new)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .submitLabel(.next)
                .onSubmit { focusedField = .confirm }

            SecureField("Confirm new password", text: $confirmPassword)
                .textContentType(.newPassword)
                .focused($focusedField, equals: .confirm)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .submitLabel(.go)
                .onSubmit { if canSubmit { submit() } }
        }
    }

    private var submitButton: some View {
        MarquePrimaryButton("Update Password", isLoading: isProcessing) {
            submit()
        }
        .disabled(!canSubmit || isProcessing)
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

            Text("Password Updated")
                .font(.title3).fontWeight(.bold)
        }
    }

    // MARK: - Actions

    private func submit() {
        // Client-side validation before ever calling Firebase.
        if let validationError {
            errorMessage = validationError
            return
        }
        errorMessage = nil
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                try await authService.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                didSucceed = true
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            } catch {
                errorMessage = friendlyError(error)
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain {
            switch AuthErrorCode(rawValue: nsError.code) {
            case .wrongPassword:
                return "Current password is incorrect."
            case .weakPassword:
                return "New password is too weak. Choose a stronger password."
            case .tooManyRequests:
                return "Too many attempts. Please try again later."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
