import SwiftUI

struct PublicProfileView: View {
    let ownerUID: String
    let ownerUsername: String

    @EnvironmentObject var exploreStore: ExploreStore
    @EnvironmentObject var followStore: FollowStore
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var blockStore: BlockStore

    @State private var profile: PublicUserProfile?
    @State private var followerUIDs: Set<String> = []
    @State private var followingUIDs: Set<String> = []
    @State private var showingUnfollowAlert = false
    @State private var showingBlockAlert = false
    @State private var showingReport = false
    @State private var showingFollowers = false
    @State private var showingFollowing = false

    private var cars: [PublicCar] { exploreStore.cars(for: ownerUID) }
    private var isOwnProfile: Bool { authService.currentUser?.id == ownerUID }
    private var isFollowing: Bool { followStore.isFollowing(ownerUID) }
    private var isBlocked: Bool { blockStore.isBlocked(ownerUID) }
    private var currentUID: String { authService.currentUser?.id ?? "" }

    var body: some View {
        Group {
            if isBlocked {
                MarqueEmptyState(
                    icon: "person.crop.circle.badge.minus",
                    title: "User Blocked",
                    subtitle: "You've blocked this user. Unblock them from the menu to see their profile."
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        profileHeader
                        Divider().padding(.vertical, 8)
                        carsGrid
                    }
                }
            }
        }
        .navigationTitle("@\(ownerUsername)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            exploreStore.loadProStatus(for: [ownerUID])
            profile = await exploreStore.fetchUserProfile(uid: ownerUID)
            let edges = await exploreStore.fetchFollowUIDs(uid: ownerUID)
            followerUIDs = edges.followers
            followingUIDs = edges.following
        }
        // Keep the visible follower count in sync when the current user follows
        // or unfollows the profile owner. Foreign follow-graph changes (someone
        // else follows this profile while we're viewing it) still require a
        // re-open to refresh, which is acceptable for MVP.
        .onChange(of: isFollowing) { _, nowFollowing in
            guard !currentUID.isEmpty, currentUID != ownerUID else { return }
            if nowFollowing { followerUIDs.insert(currentUID) }
            else { followerUIDs.remove(currentUID) }
        }
        .toolbar {
            if !isOwnProfile {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) { showingBlockAlert = true } label: {
                            Label(isBlocked ? "Unblock @\(ownerUsername)" : "Block @\(ownerUsername)",
                                  systemImage: isBlocked ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.minus")
                        }
                        Button(role: .destructive) { showingReport = true } label: {
                            Label("Report @\(ownerUsername)", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert(
            isBlocked ? "Unblock @\(ownerUsername)?" : "Block @\(ownerUsername)?",
            isPresented: $showingBlockAlert
        ) {
            Button(isBlocked ? "Unblock" : "Block", role: .destructive) {
                Task {
                    if isBlocked { await blockStore.unblock(uid: ownerUID) }
                    else { await blockStore.block(uid: ownerUID) }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if !isBlocked {
                Text("@\(ownerUsername) won't be able to see your profile or cars.")
            }
        }
        .alert("Unfollow @\(ownerUsername)?", isPresented: $showingUnfollowAlert) {
            Button("Unfollow", role: .destructive) {
                Task { await followStore.unfollow(uid: ownerUID) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingReport) {
            ReportView(title: "Report User", reportedUID: ownerUID)
                .environmentObject(blockStore)
        }
        .sheet(isPresented: $showingFollowers) {
            FollowListView(mode: .followers, uids: followerUIDs, currentUserUID: currentUID)
        }
        .sheet(isPresented: $showingFollowing) {
            FollowListView(mode: .following, uids: followingUIDs, currentUserUID: currentUID)
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                avatarView
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(profile?.displayName ?? ownerUsername)
                            .font(.headline)
                        if exploreStore.isPro(ownerUID) { ProBadge() }
                    }
                    Text("@\(ownerUsername)")
                        .font(.subheadline).foregroundColor(.secondary)
                }

                Spacer()

                if !isOwnProfile {
                    FollowButton(isFollowing: isFollowing) {
                        if isFollowing {
                            showingUnfollowAlert = true
                        } else {
                            Task {
                                await followStore.follow(
                                    uid: ownerUID,
                                    actorDisplayName: authService.currentUser?.displayName ?? "",
                                    actorUsername: authService.currentUser?.username ?? "",
                                    actorAvatarURL: authService.currentUser?.avatarURL
                                )
                            }
                        }
                    }
                }
            }

            if let bio = profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 0) {
                StatChip(value: "\(cars.count)", label: "Cars")
                Divider().frame(height: 30).padding(.horizontal, 16)
                StatChip(value: "\(followerUIDs.count)", label: "Followers") {
                    showingFollowers = true
                }
                Divider().frame(height: 30).padding(.horizontal, 16)
                StatChip(value: "\(followingUIDs.count)", label: "Following") {
                    showingFollowing = true
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = profile?.avatarURL,
           !urlString.isEmpty,
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
                Text(ownerUsername.prefix(1).uppercased())
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.accentColor)
            )
    }

    // MARK: - Cars Grid

    private var carsGrid: some View {
        VStack(spacing: 0) {
            MarqueSectionHeader(title: "Cars")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if cars.isEmpty {
                MarqueEmptyState(
                    icon: "car.fill",
                    title: "No Public Cars",
                    subtitle: "This user hasn't shared any cars yet."
                )
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(cars) { car in
                        NavigationLink(destination: CarDetailView(publicCar: car)
                            .environmentObject(exploreStore)) {
                            ExploreCarCell(car: car)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }
}
