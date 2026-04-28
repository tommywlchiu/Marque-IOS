import SwiftUI

struct FollowListView: View {
    @Environment(\.dismiss) var dismiss

    let title: String
    let users: [AppUser]

    @State private var searchText = ""

    private var filtered: [AppUser] {
        guard !searchText.isEmpty else { return users }
        let q = searchText.lowercased()
        return users.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.username.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if users.isEmpty {
                    MarqueEmptyState(
                        icon: "person.2",
                        title: "No \(title) Yet",
                        subtitle: "When people follow this account, they'll show up here."
                    )
                } else {
                    List(filtered) { user in
                        NavigationLink(destination: PublicProfileView(user: user)) {
                            UserRow(user: user)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search \(title.lowercased())")
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - User Row

private struct UserRow: View {
    let user: AppUser
    @State private var isFollowing: Bool

    init(user: AppUser) {
        self.user = user
        _isFollowing = State(initialValue: user.isFollowing)
    }

    var body: some View {
        HStack(spacing: 12) {
            UserAvatar(user: user, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.displayName)
                        .font(.subheadline).fontWeight(.semibold)
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            FollowButton(isFollowing: isFollowing) {
                isFollowing.toggle()
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FollowListView(title: "Followers", users: AppUser.previewFollowers)
}
