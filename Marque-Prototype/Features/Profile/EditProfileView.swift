import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var location = ""

    private var hasChanges: Bool {
        let user = authService.currentUser ?? .preview
        return displayName != user.displayName ||
               username != user.username ||
               bio != user.bio ||
               location != user.location
    }

    var body: some View {
        NavigationStack {
            Form {
                avatarSection
                infoSection
                bioSection
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!hasChanges)
                }
            }
            .onAppear { populateFields() }
        }
    }

    // MARK: - Sections

    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    if let user = authService.currentUser {
                        UserAvatar(user: user, size: 80)
                    }
                    Button("Change Photo") { /* photo picker — wire up PhotosPicker */ }
                        .font(.subheadline)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)
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

    private func save() {
        authService.updateProfile(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location.trimmingCharacters(in: .whitespaces)
        )
        dismiss()
    }
}

#Preview {
    EditProfileView()
        .environmentObject(AuthService())
}
