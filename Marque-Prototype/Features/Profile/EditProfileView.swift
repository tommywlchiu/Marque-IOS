import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var location = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var hasChanges: Bool {
        let user = authService.currentUser ?? .preview
        return avatarImage != nil ||
               displayName != user.displayName ||
               username != user.username ||
               bio != user.bio ||
               location != user.location
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
                avatarSection
                infoSection
                bioSection
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Button("Save") { Task { await save() } }
                                .fontWeight(.semibold)
                                .disabled(!hasChanges)
                        }
                    }
                }
            }
            .onAppear { populateFields() }
            .onChange(of: selectedItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        avatarImage = image
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    avatarPreview
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Text("Change Photo")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let image = avatarImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
        } else if let user = authService.currentUser {
            UserAvatar(user: user, size: 80)
        }
    }

    private var infoSection: some View {
        Section(header: Text("Your Info")) {
            LabeledContent("Name") {
                TextField("Full Name", text: $displayName)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }

            LabeledContent("Username") {
                HStack(spacing: 4) {
                    Text("@").foregroundColor(.secondary)
                    TextField("username", text: $username)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            LabeledContent("Location") {
                TextField("City, State", text: $location)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
        }
    }

    private var bioSection: some View {
        Section(header: Text("Bio"), footer: Text("\(bio.count)/160 characters")) {
            TextEditor(text: $bio)
                .frame(minHeight: 80)
                .onChange(of: bio) { _, new in
                    if new.count > 160 { bio = String(new.prefix(160)) }
                }
        }
    }

    // MARK: - Actions

    private func populateFields() {
        let user = authService.currentUser ?? .preview
        displayName = user.displayName
        username = user.username
        bio = user.bio
        location = user.location
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let currentUsername = authService.currentUser?.username ?? ""

        if trimmedUsername != currentUsername {
            do {
                try await authService.changeUsername(to: trimmedUsername)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        var avatarFileName: String? = nil
        if let image = avatarImage, let uid = authService.currentUser?.id {
            let fileName = "avatar-\(uid).jpg"
            ImageManager.saveImage(image, fileName: fileName)
            avatarFileName = fileName
        }
        authService.updateProfile(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            username: authService.currentUser?.username ?? trimmedUsername,
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location.trimmingCharacters(in: .whitespaces),
            avatarFileName: avatarFileName
        )
        dismiss()
    }
}
