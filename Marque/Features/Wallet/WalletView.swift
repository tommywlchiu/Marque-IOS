import SwiftUI

/// Wallet tab: profile (moved from the old Garage list's header)
/// plus every document the user stores in Marque — driver's license, and each
/// car's specs, insurance, registration and warranty — presented
/// Apple-Wallet-style. Editing always routes to the existing screens
/// (EditProfileView, EditVehicleDetailsSheet, EditInsuranceSheet,
/// EditRegistrationSheet, EditWarrantySheet); this file never duplicates
/// that logic.
/// One divider in the Wallet's binder: the driver's license, or one car.
/// Selecting a tab shows only that section's cards — the old layout stacked
/// every car's four cards one after another in a single scroll, which grew
/// unreadable past two or three cars (owner: "more compact and easier to
/// navigate through, binder/folder organization").
enum WalletTab: Hashable {
    case license
    case car(UUID)
}

struct WalletView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var followStore: FollowStore

    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var showingFollowers = false
    @State private var showingFollowing = false
    @State private var editingSpecsCar: Car?
    @State private var editingInsuranceCar: Car?
    @State private var editingRegistrationCar: Car?
    @State private var editingWarrantyCar: Car?
    @State private var selectedTab: WalletTab?

    private var user: AppUser { authService.currentUser ?? .preview }

    /// License first (always present, filled or an "Add" prompt — the one
    /// entry point into it), then one tab per car in garage order.
    private var tabs: [WalletTab] {
        [.license] + carStore.cars.map { .car($0.id) }
    }

    /// Falls back to the first tab if nothing's been picked yet, or the
    /// selected car was deleted out from under the open tab.
    private var currentTab: WalletTab {
        if let selectedTab, tabs.contains(selectedTab) { return selectedTab }
        return tabs.first ?? .license
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed, not scrolled away: short and bounded (avatar, name,
                // one-line bio, stats), and keeping it in view means the tab
                // strip below is always reachable without scrolling back up
                // — part of "more compact and easier to navigate."
                profileHeader
                Divider().padding(.top, 8)

                if hasAnyDocumentSurface {
                    WalletTabStrip(tabs: tabs, selected: currentTab, title: tabTitle, icon: tabIcon) { tab in
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            selectedTab = tab
                        }
                    }
                    ScrollView {
                        tabContent(for: currentTab)
                            // A fresh identity per tab, so SwiftUI treats a
                            // switch as the old content leaving and the new
                            // one entering — not a diff of two card stacks —
                            // which is what makes the transition read as one
                            // card pulling up to replace another rather than
                            // everything just fading.
                            .id(currentTab)
                            .padding(16)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    }
                } else {
                    MarqueEmptyState(
                        icon: "wallet.pass.fill",
                        title: "No Documents Yet",
                        subtitle: "Add your driver's license or a car to see its insurance and registration here.",
                        actionTitle: "Add Driver's License",
                        action: { showingEditProfile = true }
                    )
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
                }
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
            .sheet(item: $editingSpecsCar) { car in
                EditVehicleDetailsSheet(car: car) { carStore.updateCar($0) }
            }
            .sheet(item: $editingInsuranceCar) { car in
                EditInsuranceSheet(car: car) { carStore.updateCar($0) }
            }
            .sheet(item: $editingRegistrationCar) { car in
                EditRegistrationSheet(car: car) { carStore.updateCar($0) }
            }
            .sheet(item: $editingWarrantyCar) { car in
                EditWarrantySheet(car: car) { carStore.updateCar($0) }
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

    // MARK: - Documents (binder tabs)

    /// True once there's at least one document surface to show — either the
    /// license card or a car (which always gets Insurance/Registration cards,
    /// filled or "Add…" prompts). False only when there's truly nothing: no
    /// license on file and no cars yet.
    private var hasAnyDocumentSurface: Bool {
        !user.driverLicenseNumber.isEmpty || !carStore.cars.isEmpty
    }

    private func tabTitle(_ tab: WalletTab) -> String {
        switch tab {
        case .license: return "License"
        case .car(let id): return carStore.cars.first { $0.id == id }?.displayName ?? "Car"
        }
    }

    private func tabIcon(_ tab: WalletTab) -> String {
        switch tab {
        case .license: return "person.text.rectangle.fill"
        case .car: return "car.fill"
        }
    }

    @ViewBuilder
    private func tabContent(for tab: WalletTab) -> some View {
        switch tab {
        case .license:
            licenseCard
        case .car(let id):
            if let car = carStore.cars.first(where: { $0.id == id }) {
                carDocumentsGroup(for: car)
            }
        }
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

    /// The four document cards in a 2-column grid (not stacked full-width)
    /// so one car's whole binder tab fits without much scrolling.
    @ViewBuilder
    private func carDocumentsGroup(for car: Car) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            if car.trim.isEmpty && car.bodyStyle.isEmpty && car.driveType.isEmpty
                && car.engine.isEmpty && car.fuelType.isEmpty && car.transmission.isEmpty && car.color.isEmpty {
                AddDocumentCard(
                    title: "Add Specs",
                    subtitle: "Trim, engine and more",
                    icon: "list.bullet.rectangle.fill",
                    compact: true
                ) {
                    editingSpecsCar = car
                }
            } else {
                SpecsCard(car: car) { editingSpecsCar = car }
            }

            if car.insuranceProvider.isEmpty && car.insurancePolicyNumber.isEmpty && car.insuranceExpiryDate == nil {
                AddDocumentCard(
                    title: "Add Insurance",
                    subtitle: "Track the policy",
                    icon: "shield.fill",
                    compact: true
                ) {
                    editingInsuranceCar = car
                }
            } else {
                InsuranceCard(car: car) { editingInsuranceCar = car }
            }

            if car.licensePlate.isEmpty && car.registrationExpiryDate == nil {
                AddDocumentCard(
                    title: "Add Registration",
                    subtitle: "Track the registration",
                    icon: "doc.text.fill",
                    compact: true
                ) {
                    editingRegistrationCar = car
                }
            } else {
                RegistrationCard(car: car) { editingRegistrationCar = car }
            }

            if car.warrantyProvider.isEmpty && car.warrantyType.isEmpty {
                AddDocumentCard(
                    title: "Add Warranty",
                    subtitle: "Track coverage",
                    icon: "checkmark.seal.fill",
                    compact: true
                ) {
                    editingWarrantyCar = car
                }
            } else {
                WarrantyCard(car: car) { editingWarrantyCar = car }
            }
        }
    }
}
