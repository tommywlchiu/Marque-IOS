import SwiftUI

struct CarListView: View {
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var followStore: FollowStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var appDelegate: AppDelegate

    @State private var navigationPath: [UUID] = []
    @State private var showingSettings = false
    @State private var showingAddCar = false
    @State private var showingPaywall = false
    @State private var showingEditProfile = false
    @State private var showingFollowers = false
    @State private var showingFollowing = false
    /// Car opened from a comment push; its page opens the comments sheet.
    @State private var commentsDeepLinkCarID: UUID?

    private var user: AppUser { authService.currentUser ?? .preview }

    private var atCarLimit: Bool {
        carStore.cars.count >= CarStore.freeCarLimit && !subscriptionStore.isPro
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    Divider().padding(.vertical, 8)
                    carsSection
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Garage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView()
            }
            .navigationDestination(for: UUID.self) { carId in
                if let car = carStore.cars.first(where: { $0.id == carId }) {
                    CarDetailView(car: car, openComments: commentsDeepLinkCarID == carId)
                }
            }
            .sheet(isPresented: $showingAddCar) {
                AddCarView()
            }
            .sheet(isPresented: $showingPaywall) {
                ProUpgradeView(trigger: .carLimit)
                    .environmentObject(subscriptionStore)
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showingFollowers) {
                FollowListView(mode: .followers, uids: followStore.followerUIDs, currentUserUID: user.id)
            }
            .sheet(isPresented: $showingFollowing) {
                FollowListView(mode: .following, uids: followStore.followingUIDs, currentUserUID: user.id)
            }
            .onChange(of: appDelegate.pendingCarID) { _, _ in tryDeepLinkNavigation() }
            .onChange(of: carStore.cars) { _, _ in tryDeepLinkNavigation() }
            .onChange(of: navigationPath) { _, path in
                if let id = commentsDeepLinkCarID, !path.contains(id) { commentsDeepLinkCarID = nil }
            }
            .overlay(alignment: .bottomTrailing) {
                AskMarqueDock(mode: .present)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
        .modifier(FollowPushRouter())
    }

    // Navigate to the pending car ID, if it's already in the local store.
    // Called on both pendingCarID and cars changes so a late Firestore snapshot
    // still resolves correctly when the app was cold-launched via a notification.
    private func tryDeepLinkNavigation() {
        guard let carID = appDelegate.pendingCarID,
              carStore.cars.contains(where: { $0.id == carID }) else { return }
        // A like/comment push carries the same car in `pendingPush`; consume
        // it here, and for a comment open the car's comments too.
        if let push = appDelegate.pendingPush, push.kind != .follow {
            commentsDeepLinkCarID = push.kind == .comment ? carID : nil
            appDelegate.pendingPush = nil
        }
        navigationPath = [carID]
        appDelegate.pendingCarID = nil
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                UserAvatar(user: user, size: 76)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.headline)
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue).font(.subheadline)
                        }
                        if user.isProMember {
                            ProBadge()
                        }
                    }
                    Text("@\(user.username)")
                        .font(.subheadline).foregroundColor(.secondary)
                    if !user.location.isEmpty {
                        Label(user.location, systemImage: "mappin.circle")
                            .font(.caption).foregroundColor(.secondary)
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
        .padding(.horizontal, 16)
        .padding(.top, 8)
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

    // MARK: - Cars Section

    @ViewBuilder
    private var carsSection: some View {
        if carStore.cars.isEmpty {
            emptyCarsState
        } else {
            carList
        }
    }

    private var emptyCarsState: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemGray6))
                    .frame(width: 100, height: 100)
                Image(systemName: "car.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            VStack(spacing: 6) {
                Text("Your Garage is Empty")
                    .font(.title3).fontWeight(.bold)
                Text("Add your first car to start tracking\nyour vehicle information.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                if atCarLimit { showingPaywall = true } else { showingAddCar = true }
            } label: {
                Label("Add a Car", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 28).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }

    private var carList: some View {
        LazyVStack(spacing: 14) {
            MarqueSectionHeader(title: "My Cars")
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(carStore.cars) { car in
                NavigationLink(value: car.id) {
                    CarCardView(car: car)
                }
                .buttonStyle(.plain)
            }

            Button {
                if atCarLimit { showingPaywall = true } else { showingAddCar = true }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill").font(.title3)
                    Text("Add a Car").fontWeight(.medium)
                }
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor.opacity(0.3),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                )
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

struct CarCardView: View {
    let car: Car

    private var carColorDot: Color {
        switch car.color.lowercased() {
        case "black": return .black
        case "white": return .white
        case "silver", "gray", "grey": return .gray
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "brown": return .brown
        case "purple": return .purple
        default: return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            carThumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(car.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    if !car.color.isEmpty {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(carColorDot)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                                )
                            Text(car.color)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !car.licensePlate.isEmpty {
                        Text(car.licensePlate)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                if car.hasExpiryWarning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                        Text(car.isInsuranceExpired || car.isRegistrationExpired ? "Action needed" : "Expiring soon")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(car.isInsuranceExpired || car.isRegistrationExpired ? .red : .orange)
                } else if !car.maintenanceRecords.isEmpty {
                    Text("\(car.maintenanceRecords.count) service record\(car.maintenanceRecords.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.accentColor.opacity(0.8))
                } else if car.color.isEmpty && car.licensePlate.isEmpty {
                    Text("Tap to add details")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var carThumbnail: some View {
        if let fileName = car.primaryPhotoFileName {
            CarPhotoImage(fileName: fileName, storageURL: car.primaryPhotoStorageURL)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
    }
}
