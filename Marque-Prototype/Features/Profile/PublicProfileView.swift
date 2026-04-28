import SwiftUI

struct PublicProfileView: View {
    let user: AppUser

    @State private var isFollowing: Bool
    @State private var followerCount: Int
    @State private var selectedTab: ProfileTab = .cars

    private enum ProfileTab: String, CaseIterable {
        case cars = "Cars"
        case about = "About"
    }

    // Preview cars for this user
    private let previewCars: [Car] = Array(CarStore.previewCars.prefix(2))

    init(user: AppUser) {
        self.user = user
        _isFollowing = State(initialValue: user.isFollowing)
        _followerCount = State(initialValue: user.followerCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader
                Divider()
                tabPicker
                tabContent
            }
        }
        .navigationTitle(user.username.isEmpty ? user.displayName : "@\(user.username)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                UserAvatar(user: user, size: 72)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.headline)
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

                FollowButton(isFollowing: isFollowing) { toggleFollow() }
            }

            if !user.bio.isEmpty {
                Text(user.bio)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 0) {
                StatChip(value: "\(previewCars.count)", label: "Cars")
                Divider().frame(height: 30).padding(.horizontal, 16)
                StatChip(value: "\(followerCount)", label: "Followers")
                Divider().frame(height: 30).padding(.horizontal, 16)
                StatChip(value: "\(user.followingCount)", label: "Following")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .cars: carsTab
        case .about: aboutTab
        }
    }

    private var carsTab: some View {
        Group {
            if previewCars.isEmpty {
                MarqueEmptyState(
                    icon: "car.fill",
                    title: "No Public Cars",
                    subtitle: "\(user.displayName) hasn't shared any cars yet."
                )
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(previewCars) { car in
                        NavigationLink(destination: PublicCarDetailView(car: car, owner: user)) {
                            PublicCarCell(car: car)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !user.bio.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bio").font(.caption).foregroundColor(.secondary)
                    Text(user.bio).font(.subheadline)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Member Since").font(.caption).foregroundColor(.secondary)
                Text(user.joinedDate, style: .date).font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Actions

    private func toggleFollow() {
        isFollowing.toggle()
        followerCount += isFollowing ? 1 : -1
    }
}

// MARK: - Public Car Cell

struct PublicCarCell: View {
    let car: Car

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.08))
                    .aspectRatio(1.4, contentMode: .fit)

                if let fileName = car.photoFileName,
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

#Preview {
    NavigationStack {
        PublicProfileView(user: .preview)
    }
    .environmentObject(AuthService())
}
