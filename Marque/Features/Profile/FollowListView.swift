import SwiftUI

struct FollowListView: View {
    enum Mode { case following, followers }

    let mode: Mode
    let uids: Set<String>
    let currentUserUID: String

    @EnvironmentObject var exploreStore: ExploreStore
    @EnvironmentObject var followStore: FollowStore
    @EnvironmentObject var blockStore: BlockStore
    @Environment(\.dismiss) var dismiss

    @State private var profiles: [PublicUserProfile] = []
    @State private var isLoading = true
    @State private var searchText = ""

    private var title: String { mode == .following ? "Following" : "Followers" }

    private var filtered: [PublicUserProfile] {
        guard !searchText.isEmpty else { return profiles }
        let q = searchText.lowercased()
        return profiles.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.username.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if profiles.isEmpty {
                    MarqueEmptyState(
                        icon: "person.2",
                        title: "No \(title) Yet",
                        subtitle: mode == .following
                            ? "Follow people to see them here."
                            : "When people follow you, they'll show up here."
                    )
                } else {
                    List(filtered, id: \.uid) { profile in
                        NavigationLink(
                            destination: PublicProfileView(
                                ownerUID: profile.uid ?? "",
                                ownerUsername: profile.username
                            )
                            .environmentObject(exploreStore)
                            .environmentObject(followStore)
                            .environmentObject(blockStore)
                        ) {
                            FollowUserRow(profile: profile, currentUserUID: currentUserUID)
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
            .task(id: uids) { await load() }
        }
    }

    private func load() async {
        isLoading = true
        var loaded: [PublicUserProfile] = []
        await withTaskGroup(of: PublicUserProfile?.self) { group in
            for uid in uids {
                group.addTask { await exploreStore.fetchUserProfile(uid: uid) }
            }
            for await profile in group {
                if let profile { loaded.append(profile) }
            }
        }
        profiles = loaded.sorted { $0.username < $1.username }
        isLoading = false
    }
}

// MARK: - Row

private struct FollowUserRow: View {
    let profile: PublicUserProfile
    let currentUserUID: String

    @EnvironmentObject var followStore: FollowStore
    @EnvironmentObject var authService: AuthService
    @State private var showingUnfollowAlert = false

    private var uid: String { profile.uid ?? "" }
    private var isFollowing: Bool { followStore.isFollowing(uid) }
    private var isOwnProfile: Bool { uid == currentUserUID }

    var body: some View {
        HStack(spacing: 12) {
            avatarView
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.subheadline).fontWeight(.semibold)
                Text("@\(profile.username)")
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            if !isOwnProfile {
                FollowButton(isFollowing: isFollowing) {
                    if isFollowing { showingUnfollowAlert = true }
                    else {
                        Task {
                            await followStore.follow(
                                uid: uid,
                                actorDisplayName: authService.currentUser?.displayName ?? "",
                                actorUsername: authService.currentUser?.username ?? "",
                                actorAvatarURL: authService.currentUser?.avatarURL
                            )
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Unfollow @\(profile.username)?", isPresented: $showingUnfollowAlert) {
            Button("Unfollow", role: .destructive) {
                Task { await followStore.unfollow(uid: uid) }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = profile.avatarURL.isEmpty ? nil : profile.avatarURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: initialsCircle
                }
            }
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .overlay(
                Text(profile.username.prefix(1).uppercased())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.accentColor)
            )
    }
}
