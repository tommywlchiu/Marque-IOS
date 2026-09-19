import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @EnvironmentObject var authService: AuthService

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var availability: UsernameAvailability = .empty
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canContinue: Bool {
        availability == .available && !isSubmitting
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                avatarPicker
                nameField
                usernameField
                bioField
                continueButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            let name = authService.currentUser?.displayName ?? ""
            if name != "User" { displayName = name }
            // Gated on isFreshOnboarding, like LoginView: this screen is also reached
            // by a returning user whose Firestore lookup failed, or by someone
            // relaunching mid-setup — neither is a fresh pass through the FR-13.2
            // funnel, and counting them would distort the R-01 drop-off metric.
            if authService.isFreshOnboarding {
                AnalyticsService.onboardingStepViewed(step: .profileSetup)
            }
        }
        .onChange(of: selectedItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    avatarImage = image
                }
            }
        }
        .onChange(of: username) { _, new in
            scheduleAvailabilityCheck(for: new)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Set Up Your Profile")
                .font(.title2).fontWeight(.bold)
            Text("Choose a username to get started.\nYou can always update your profile later.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Avatar

    private var avatarPicker: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image = avatarImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.accentColor.opacity(0.5))
                            )
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 3))

                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 32, height: 32)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Name")
                    .font(.subheadline).fontWeight(.semibold)
                Text("Optional")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
            TextField("Your name", text: $displayName)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 1.5))
        }
    }

    // MARK: - Username

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Username")
                .font(.subheadline).fontWeight(.semibold)

            HStack(spacing: 8) {
                Text("@")
                    .foregroundColor(.secondary)
                    .font(.body)

                TextField("yourname", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)

                availabilityIndicator
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1.5)
            )

            if let hint = availabilityHint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(hintColor)
                    .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private var availabilityIndicator: some View {
        switch availability {
        case .checking:
            ProgressView().scaleEffect(0.8)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .taken:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        default:
            EmptyView()
        }
    }

    private var borderColor: Color {
        switch availability {
        case .available: return .green.opacity(0.6)
        case .taken, .tooShort, .tooLong, .invalidChars: return .red.opacity(0.5)
        default: return Color(.separator)
        }
    }

    private var availabilityHint: String? {
        switch availability {
        case .empty: return "3–30 characters, letters, numbers and underscores only."
        case .tooShort: return "Must be at least 3 characters."
        case .tooLong: return "Must be 30 characters or fewer."
        case .invalidChars: return "Only letters, numbers and underscores (_) allowed."
        case .checking: return nil
        case .available: return "@\(username.lowercased()) is available."
        case .taken: return "@\(username.lowercased()) is already taken."
        }
    }

    private var hintColor: Color {
        switch availability {
        case .available: return .green
        case .taken, .tooShort, .tooLong, .invalidChars: return .red
        default: return .secondary
        }
    }

    // MARK: - Bio

    private var bioField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bio")
                    .font(.subheadline).fontWeight(.semibold)
                Text("Optional")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            ZStack(alignment: .topLeading) {
                if bio.isEmpty {
                    Text("Tell people a bit about yourself…")
                        .foregroundColor(Color(.placeholderText))
                        .font(.body)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $bio)
                    .font(.body)
                    .frame(minHeight: 80)
                    .onChange(of: bio) { _, new in
                        if new.count > 160 { bio = String(new.prefix(160)) }
                    }
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("\(bio.count)/160")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
        }
    }

    // MARK: - Continue

    private var continueButton: some View {
        VStack(spacing: 12) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Get Started")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Logic

    private func scheduleAvailabilityCheck(for input: String) {
        usernameCheckTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty { availability = .empty; return }
        if trimmed.count < 3 { availability = .tooShort; return }
        if trimmed.count > 30 { availability = .tooLong; return }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if !trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            availability = .invalidChars; return
        }

        availability = .checking
        usernameCheckTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let isAvailable = await authService.checkUsernameAvailability(trimmed)
            availability = isAvailable ? .available : .taken
        }
    }

    private func submit() async {
        guard canContinue else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await authService.completeProfileSetup(
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                username: username.trimmingCharacters(in: .whitespaces),
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarImage: avatarImage
            )
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}

enum UsernameAvailability: Equatable {
    case empty, tooShort, tooLong, invalidChars, checking, available, taken
}
