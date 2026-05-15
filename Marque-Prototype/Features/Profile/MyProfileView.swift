import SwiftUI

struct MyProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var followStore: FollowStore
    @State private var showingEditProfile = false
    @State private var showingFollowers = false
    @State private var showingFollowing = false

    private var user: AppUser { authService.currentUser ?? .preview }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    Divider().padding(.vertical, 8)
                    carsGrid
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingEditProfile = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showingFollowers) {
                FollowListView(mode: .followers, currentUserUID: user.id)
            }
            .sheet(isPresented: $showingFollowing) {
                FollowListView(mode: .following, currentUserUID: user.id)
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                UserAvatar(user: user, size: 80)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.title3).fontWeight(.bold)
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                                .font(.subheadline)
                        }
                        if user.isProMember {
                            ProBadge()
                        }
                    }

                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if !user.location.isEmpty {
                        Label(user.location, systemImage: "mappin.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            if !user.bio.isEmpty {
                Text(user.bio)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            statsRow

            Button("Edit Profile") { showingEditProfile = true }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .controlSize(.regular)
        }
        .padding(16)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            StatChip(value: "\(carStore.cars.count)", label: "Cars")
            Divider().frame(height: 30).padding(.horizontal, 16)
            StatChip(value: "\(followStore.followerCount)", label: "Followers") {
                showingFollowers = true
            }
            Divider().frame(height: 30).padding(.horizontal, 16)
            StatChip(value: "\(followStore.followingCount)", label: "Following") {
                showingFollowing = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Cars Grid

    private var carsGrid: some View {
        VStack(spacing: 0) {
            MarqueSectionHeader(title: "My Cars")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if carStore.cars.isEmpty {
                MarqueEmptyState(
                    icon: "car.fill",
                    title: "No Cars Yet",
                    subtitle: "Cars you add to your garage will appear here."
                )
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(carStore.cars) { car in
                        ProfileCarCell(car: car)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Profile Car Cell

private struct ProfileCarCell: View {
    let car: Car

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.08))
                    .aspectRatio(1.4, contentMode: .fit)

                if let fileName = car.primaryPhotoFileName,
                   let uiImage = ImageManager.loadImage(fileName: fileName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "car.fill")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor.opacity(0.5))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(car.displayName)
                    .font(.caption).fontWeight(.semibold)
                    .lineLimit(1)
                if !car.color.isEmpty {
                    Text(car.color)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}
