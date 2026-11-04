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

    /// Stable string id for persisting the order ("license" or the car's UUID).
    var storageID: String {
        switch self {
        case .license: return WalletOrder.licenseID
        case .car(let id): return id.uuidString
        }
    }
}

/// The owner's drag-arranged order of Wallet cards, kept on the device. Cars
/// and the license are ids; anything not in the saved list yet (a new car) goes
/// on top, anything no longer present (a deleted car) is ignored. Favoriting a
/// car moves it to the front (`CarStore.toggleFavorite`).
enum WalletOrder {
    static let key = "marque_wallet_order"
    static let licenseID = "license"

    static func load() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func save(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: key) }

    /// `base` is the default order (favorites first, license last); `saved`
    /// the owner's arrangement. Unknown ids drop out, new ones lead.
    static func apply(base: [String], saved: [String]) -> [String] {
        let known = Set(base)
        var seen = Set<String>()
        let kept = saved.filter { known.contains($0) && seen.insert($0).inserted }
        return base.filter { !seen.contains($0) } + kept
    }

    /// Puts `id` first, but only once the owner has arranged the cards (with no
    /// saved order, favorites already lead by default).
    static func moveToFront(_ id: String) {
        var ids = load()
        guard !ids.isEmpty else { return }
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        save(ids)
    }
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
    /// The card brought forward, or nil for the stack.
    @State private var openCard: WalletTab?
    @Namespace private var cardNamespace
    /// The owner's saved arrangement (see `WalletOrder`).
    @State private var savedOrder: [String] = WalletOrder.load()
    // Drag-to-reorder: the card being moved, how far it has been dragged, the
    // index it started from, and the order as it would be if dropped now.
    @State private var dragging: WalletTab?
    @State private var dragOffset: CGFloat = 0
    @State private var dragStartIndex = 0
    @State private var liveOrder: [WalletTab]?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var user: AppUser { authService.currentUser ?? .preview }

    /// The stack, top to bottom: favorite cars, the other cars (garage
    /// order), then the license. In Apple Wallet the last card sits in front,
    /// fully visible, with the earlier ones peeking out above it.
    private var tabs: [WalletTab] {
        let base: [WalletTab] = carStore.orderedCars.map { .car($0.id) } + [.license]
        let byID = Dictionary(base.map { ($0.storageID, $0) }, uniquingKeysWith: { first, _ in first })
        return WalletOrder.apply(base: base.map(\.storageID), saved: savedOrder).compactMap { byID[$0] }
    }

    /// The open card, unless it has since disappeared (a deleted car).
    private var currentOpen: WalletTab? {
        guard let openCard, tabs.contains(openCard) else { return nil }
        return openCard
    }

    private func car(for tab: WalletTab) -> Car? {
        guard case .car(let id) = tab else { return nil }
        return carStore.cars.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed, not scrolled away: short and bounded (avatar, name,
                // one-line bio, stats), and keeping it in view means the tab
                // strip below is always reachable without scrolling back up
                // — part of "more compact and easier to navigate."
                profileHeader

                if hasAnyDocumentSurface {
                    if let open = currentOpen {
                        openCardView(open)
                            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    } else {
                        cardStack
                            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
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
                if currentOpen != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { openCard = nil }
                        } label: {
                            Label("All Cards", systemImage: "chevron.down")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
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
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                UserAvatar(user: user, size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.headline)
                            .lineLimit(1)
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
                    if !user.bio.isEmpty {
                        Text(user.bio)
                            .font(.caption).foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button("Edit") { showingEditProfile = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Edit Profile")
            }

            statsRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
        .padding(.vertical, 6)
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

    // MARK: - Card stack (Apple Wallet style)

    private static let peek: CGFloat = 78
    private var spring: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82) }

    private var cardStack: some View {
        let order = liveOrder ?? tabs
        return ScrollView {
            // Cards are placed by index (each one `peek` below the last), not
            // stacked in a VStack, so a dragged card can follow the finger
            // while its neighbours slide to make room.
            ZStack(alignment: .top) {
                ForEach(Array(order.enumerated()), id: \.element) { index, tab in
                    let isDragging = dragging == tab
                    stackCard(for: tab)
                        .matchedGeometryEffect(id: tab, in: cardNamespace)
                        .scaleEffect(isDragging ? 1.03 : 1)
                        .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: 18, y: 8)
                        .offset(y: isDragging
                            ? CGFloat(dragStartIndex) * Self.peek + dragOffset
                            : CGFloat(index) * Self.peek)
                        .zIndex(isDragging ? 100 : Double(index))
                        .onTapGesture { open(tab) }
                        .gesture(reorderGesture(for: tab))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Move up") { move(tab, by: -1) }
                        .accessibilityAction(named: "Move down") { move(tab, by: 1) }
                }
            }
            .frame(height: CGFloat(max(order.count - 1, 0)) * Self.peek + WalletStackCard.height, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .animation(spring, value: order)
        }
        .scrollDisabled(dragging != nil)
        .onChange(of: carStore.cars) { _, _ in savedOrder = WalletOrder.load() }
    }

    /// Press and hold a card, then drag it up or down: the others make room,
    /// and the new order is saved when you let go.
    private func reorderGesture(for tab: WalletTab) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if dragging == nil { beginDrag(tab) }
                guard dragging == tab else { return }
                dragOffset = drag.translation.height
                updateLiveOrder(for: tab)
            }
            .onEnded { _ in endDrag() }
    }

    private func beginDrag(_ tab: WalletTab) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dragStartIndex = tabs.firstIndex(of: tab) ?? 0
        liveOrder = tabs
        withAnimation(spring) { dragging = tab }
    }

    private func updateLiveOrder(for tab: WalletTab) {
        guard var order = liveOrder, let current = order.firstIndex(of: tab) else { return }
        let y = CGFloat(dragStartIndex) * Self.peek + dragOffset
        let target = min(max(Int((y / Self.peek).rounded()), 0), order.count - 1)
        guard target != current else { return }
        order.move(fromOffsets: IndexSet(integer: current), toOffset: target > current ? target + 1 : target)
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(spring) { liveOrder = order }
    }

    private func endDrag() {
        if let order = liveOrder {
            let ids = order.map(\.storageID)
            WalletOrder.save(ids)
            savedOrder = ids
        }
        withAnimation(spring) {
            dragging = nil
            dragOffset = 0
        }
        // Drop the live order once the card has settled into its slot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { liveOrder = nil }
    }

    /// VoiceOver / non-drag way to rearrange: "Move up" / "Move down".
    private func move(_ tab: WalletTab, by delta: Int) {
        var order = tabs
        guard let i = order.firstIndex(of: tab) else { return }
        let j = min(max(i + delta, 0), order.count - 1)
        guard j != i else { return }
        order.move(fromOffsets: IndexSet(integer: i), toOffset: j > i ? j + 1 : j)
        let ids = order.map(\.storageID)
        WalletOrder.save(ids)
        withAnimation(spring) { savedOrder = ids }
    }

    private func open(_ tab: WalletTab) {
        Haptics.tap()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { openCard = tab }
    }

    @ViewBuilder
    private func stackCard(for tab: WalletTab) -> some View {
        if let car = car(for: tab) {
            WalletStackCard(kind: .car(car)) {
                Haptics.tap()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { carStore.toggleFavorite(car) }
            }
        } else {
            WalletStackCard(kind: .license(user))
        }
    }

    /// The tapped card at the top, its documents below (the old per-tab
    /// content, unchanged).
    private func openCardView(_ tab: WalletTab) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                stackCard(for: tab)
                    .matchedGeometryEffect(id: tab, in: cardNamespace)
                tabContent(for: tab)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .padding(16)
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
