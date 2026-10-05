import SwiftUI

/// Wallet tab: profile (moved from the old Garage list's header)
/// plus every document the user stores in Marque — driver's license, and each
/// car's insurance and registration — presented Apple-Wallet-style. Editing
/// always routes to the existing screens (EditProfileView, EditInsuranceSheet,
/// EditRegistrationSheet); this file never duplicates that logic.
struct WalletView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var followStore: FollowStore

    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var showingFollowers = false
    @State private var showingFollowing = false
    @State private var editingInsuranceCar: Car?
    @State private var editingRegistrationCar: Car?

    private var user: AppUser { authService.currentUser ?? .preview }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    Divider().padding(.vertical, 8)
                    documentsSection
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView()
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
            .sheet(item: $editingInsuranceCar) { car in
                EditInsuranceSheet(car: car) { carStore.updateCar($0) }
            }
            .sheet(item: $editingRegistrationCar) { car in
                EditRegistrationSheet(car: car) { carStore.updateCar($0) }
            }
        }
    }

    // MARK: - Profile header
    //
    // Moved verbatim (layout + navigation) from the old Garage list's
    // `profileHeader`/`statsRow`.

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

    // MARK: - Documents

    /// True once there's at least one document surface to show — either the
    /// license card or a car (which always gets Insurance/Registration cards,
    /// filled or "Add…" prompts). False only when there's truly nothing: no
    /// license on file and no cars yet.
    private var hasAnyDocumentSurface: Bool {
        !user.driverLicenseNumber.isEmpty || !carStore.cars.isEmpty
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            MarqueSectionHeader(title: "Documents")
                .padding(.horizontal, 16)

            if !hasAnyDocumentSurface {
                MarqueEmptyState(
                    icon: "wallet.pass.fill",
                    title: "No Documents Yet",
                    subtitle: "Add your driver's license or a car to see its insurance and registration here.",
                    actionTitle: "Add Driver's License",
                    action: { showingEditProfile = true }
                )
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 20) {
                    licenseCard
                    ForEach(carStore.cars) { car in
                        carDocumentsGroup(for: car)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var licenseCard: some View {
        if user.driverLicenseNumber.isEmpty && user.driverLicenseState.isEmpty && user.driverLicenseExpiryDate == nil {
            AddDocumentCard(
                title: "Add Driver's License",
                subtitle: "Keep it handy for reference — never shown to other users",
                icon: "person.text.rectangle.fill"
            ) {
                showingEditProfile = true
            }
        } else {
            DriverLicenseCard(user: user) { showingEditProfile = true }
        }
    }

    @ViewBuilder
    private func carDocumentsGroup(for car: Car) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(car.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            if car.insuranceProvider.isEmpty && car.insurancePolicyNumber.isEmpty && car.insuranceExpiryDate == nil {
                AddDocumentCard(
                    title: "Add Insurance",
                    subtitle: "Track \(car.displayName)'s policy",
                    icon: "shield.fill"
                ) {
                    editingInsuranceCar = car
                }
            } else {
                InsuranceCard(car: car) { editingInsuranceCar = car }
            }

            if car.licensePlate.isEmpty && car.registrationExpiryDate == nil {
                AddDocumentCard(
                    title: "Add Registration",
                    subtitle: "Track \(car.displayName)'s registration",
                    icon: "doc.text.fill"
                ) {
                    editingRegistrationCar = car
                }
            } else {
                RegistrationCard(car: car) { editingRegistrationCar = car }
            }
        }
    }
}
