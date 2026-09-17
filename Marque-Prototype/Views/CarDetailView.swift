import SwiftUI

/// Unified detail view that handles both the user's own car (full edit / delete /
/// expense / reminder / maintenance controls) and another user's public car
/// (owner row + report button, hides private fields).
struct CarDetailView: View {
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var exploreStore: ExploreStore
    @EnvironmentObject var blockStore: BlockStore
    @Environment(\.dismiss) var dismiss

    // Exactly one of these is non-nil. Own car is @State so mutations sync to UI.
    @State private var ownCar: Car?
    private let publicCar: PublicCar?

    @State private var showingEditDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var showingAddMaintenance = false
    @State private var showingReport = false
    @State private var showingOwnerProfile = false
    @State private var galleryStartIndex: Int?

    // Focused-sheet add/edit flows — one per section. Consolidated with the
    // above state to make it obvious that every "add/edit" surface here is a
    // sheet, not a full-form drop-in or a navigation push.
    @State private var showingEditRegistration = false
    @State private var showingEditVehicleDetails = false
    @State private var showingEditInsurance = false
    @State private var showingAddReminder = false

    init(car: Car) {
        self._ownCar = State(initialValue: car)
        self.publicCar = nil
    }

    init(publicCar: PublicCar) {
        self._ownCar = State(initialValue: nil)
        self.publicCar = publicCar
    }

    // MARK: - Mode helpers

    private var isOwnCar: Bool { ownCar != nil }

    /// The live `Car` for own-car mode — pulled from `carStore` so external updates
    /// (Firestore listener, photo upload) flow into the UI.
    private var liveCar: Car? {
        guard let car = ownCar else { return nil }
        return carStore.cars.first(where: { $0.id == car.id }) ?? car
    }

    // MARK: - Common accessors

    private var displayName: String {
        liveCar?.displayName ?? publicCar?.displayName ?? ""
    }
    private var make: String { liveCar?.make ?? publicCar?.make ?? "" }
    private var model: String { liveCar?.model ?? publicCar?.model ?? "" }
    private var year: String { liveCar?.year ?? publicCar?.year ?? "" }
    private var color: String { liveCar?.color ?? publicCar?.color ?? "" }
    private var mileage: String { liveCar?.mileage ?? publicCar?.mileage ?? "" }
    private var trim: String { liveCar?.trim ?? publicCar?.trim ?? "" }
    private var bodyStyle: String { liveCar?.bodyStyle ?? publicCar?.bodyStyle ?? "" }
    private var driveType: String { liveCar?.driveType ?? publicCar?.driveType ?? "" }
    private var engine: String { liveCar?.engine ?? publicCar?.engine ?? "" }
    private var fuelType: String { liveCar?.fuelType ?? publicCar?.fuelType ?? "" }
    private var transmission: String { liveCar?.transmission ?? publicCar?.transmission ?? "" }
    private var notes: String { liveCar?.notes ?? publicCar?.notes ?? "" }

    // MARK: - Body

    var body: some View {
        List {
            photoHeaderSection

            if let pc = publicCar {
                ownerRowSection(for: pc)
            }

            if let car = liveCar, car.hasExpiryWarning {
                expiryAlertBanner(for: car)
            }

            if liveCar != nil {
                visibilitySection
            }

            basicInfoSection

            if liveCar != nil {
                registrationSection
                vehicleDetailsSection
                insuranceSection
            } else {
                publicVehicleDetailsSection
            }

            if !notes.isEmpty {
                Section(header: Text("Notes")) {
                    Text(notes).font(.body)
                }
            }

            if let car = liveCar, car.totalExpenses > 0 {
                expenseSummarySection(for: car)
            }

            if liveCar != nil {
                remindersSection
                maintenanceSection
            } else if let pc = publicCar, !pc.serviceHistory.isEmpty {
                publicServiceHistorySection(for: pc)
            }

            if isOwnCar {
                deleteSection
            }
        }
        .navigationTitle("Car Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isOwnCar {
                    Button("Edit") { showingEditDetails = true }
                } else {
                    Button { showingReport = true } label: {
                        Image(systemName: "flag")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditDetails) {
            if let car = ownCar {
                EditCarDetailView(car: ownCarBinding(initial: car), onSave: { updatedCar in
                    ownCar = updatedCar
                    carStore.updateCar(updatedCar)
                })
            }
        }
        .sheet(isPresented: $showingAddMaintenance) {
            AddMaintenanceView { record in
                guard let car = liveCar else { return }
                ownCar = car
                ownCar?.maintenanceRecords.append(record)
                carStore.updateCar(ownCar!)
            }
        }
        .modifier(FocusedEditPresenters(
            liveCar: liveCar,
            showingEditRegistration: $showingEditRegistration,
            showingEditVehicleDetails: $showingEditVehicleDetails,
            showingEditInsurance: $showingEditInsurance,
            showingAddReminder: $showingAddReminder,
            onSave: { updated in
                ownCar = updated
                carStore.updateCar(updated)
            }
        ))
        .sheet(isPresented: $showingOwnerProfile) {
            if let pc = publicCar {
                NavigationStack {
                    PublicProfileView(ownerUID: pc.ownerUID, ownerUsername: pc.ownerUsername)
                        .environmentObject(exploreStore)
                        .environmentObject(blockStore)
                }
            }
        }
        .sheet(isPresented: $showingReport) {
            if let pc = publicCar {
                ReportView(title: "Report Car", reportedUID: pc.ownerUID, contentId: pc.carId)
                    .environmentObject(blockStore)
            }
        }
        .fullScreenCover(item: Binding(
            get: { galleryStartIndex.map(GalleryStart.init) },
            set: { galleryStartIndex = $0?.index }
        )) { start in
            galleryViewer(startIndex: start.index)
        }
        .alert("Delete Car", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let car = liveCar {
                    carStore.deleteCar(car)
                }
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete \(displayName)? This action cannot be undone.")
        }
        .overlay(alignment: .bottomTrailing) {
            if let car = liveCar {
                AskMarqueButton(scopedCarId: car.id.uuidString)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    // EditCarDetailView wants a Binding<Car>; thread it through @State ownCar.
    private func ownCarBinding(initial: Car) -> Binding<Car> {
        Binding(
            get: { ownCar ?? initial },
            set: { ownCar = $0 }
        )
    }

    // MARK: - Photo header (shared, edge-to-edge in the list)

    private var photoHeaderSection: some View {
        Section {
            VStack(spacing: 12) {
                photoHeaderContent
                Text(displayName)
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var photoHeaderContent: some View {
        if let car = liveCar, let fileName = car.primaryPhotoFileName {
            ZStack(alignment: .bottomTrailing) {
                CarPhotoImage(fileName: fileName, storageURL: car.primaryPhotoStorageURL)
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .offset(y: car.photoOffsetY)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { galleryStartIndex = 0 }

                if car.hasMultiplePhotos {
                    photoCountBadge(count: car.photoFileNames.count)
                }
            }

            if car.hasMultiplePhotos {
                photoThumbnailStrip(for: car)
            }
        } else if let pc = publicCar, let url = pc.primaryPhotoURL {
            CachedRemoteImage(url: url)
                .frame(maxWidth: .infinity).frame(height: 200)
                .offset(y: pc.photoOffsetY)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(height: 120)
                VStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor.opacity(0.4))
                    if isOwnCar {
                        Text("Tap Edit to add a photo")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func photoCountBadge(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "photo.stack").font(.caption2)
            Text("\(count)").font(.caption).fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
        .padding(10)
    }

    private func photoThumbnailStrip(for car: Car) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(car.photoFileNames.enumerated()), id: \.offset) { index, fileName in
                    Button {
                        galleryStartIndex = index
                    } label: {
                        CarPhotoImage(fileName: fileName, storageURL: car.storageURL(at: index))
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2).padding(.top, 4)
        }
    }

    @ViewBuilder
    private func galleryViewer(startIndex: Int) -> some View {
        if let car = liveCar {
            PhotoGalleryView(
                photoFileNames: car.photoFileNames,
                photoStorageURLs: car.photoStorageURLs,
                initialIndex: startIndex
            )
        } else if let pc = publicCar, let url = pc.primaryPhotoURL {
            PhotoGalleryView(
                photoFileNames: [],
                photoStorageURLs: [url.absoluteString],
                initialIndex: 0
            )
        }
    }

    // MARK: - Owner row (public only)

    private func ownerRowSection(for pc: PublicCar) -> some View {
        Section {
            Button { showingOwnerProfile = true } label: {
                HStack(spacing: 12) {
                    OwnerAvatar(avatarURL: pc.ownerAvatarURL, username: pc.ownerUsername, size: 40)
                    Text("@\(pc.ownerUsername)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Expiry banner (own only)

    private func expiryAlertBanner(for car: Car) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if car.isRegistrationExpired {
                    ExpiryBannerItem(icon: "exclamationmark.triangle.fill", text: "Registration has expired", color: .red)
                } else if car.isRegistrationExpiringSoon {
                    ExpiryBannerItem(icon: "clock.badge.exclamationmark", text: "Registration expiring soon", color: .orange)
                }
                if car.isInsuranceExpired {
                    ExpiryBannerItem(icon: "exclamationmark.triangle.fill", text: "Insurance has expired", color: .red)
                } else if car.isInsuranceExpiringSoon {
                    ExpiryBannerItem(icon: "clock.badge.exclamationmark", text: "Insurance expiring soon", color: .orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Visibility toggle (own only)

    private var visibilitySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { liveCar?.isPublic ?? false },
                set: { isPublic in
                    guard let car = liveCar else { return }
                    let username = authService.currentUser?.username ?? ""
                    let avatarURL = authService.currentUser?.avatarURL
                    carStore.setVisibility(isPublic, for: car, ownerUsername: username, ownerAvatarURL: avatarURL)
                }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Public").font(.body)
                        Text((liveCar?.isPublic ?? false)
                            ? "Visible in Explore and your public profile"
                            : "Only visible to you")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } icon: {
                    let isPublic = liveCar?.isPublic ?? false
                    Image(systemName: isPublic ? "eye.fill" : "eye.slash.fill")
                        .foregroundColor(isPublic ? .accentColor : .secondary)
                }
            }
        }
    }

    // MARK: - Basic Info (shared)

    private var basicInfoSection: some View {
        Section(header: Text("Basic Information")) {
            DetailRow(label: "Make", value: make)
            DetailRow(label: "Model", value: model)
            DetailRow(label: "Year", value: year)
        }
    }

    // MARK: - Section header / empty-row helpers
    //
    // All four editable sections (Registration, Insurance, Reminders,
    // Maintenance) use the same visual language via these helpers. The rule:
    //  - `addHeader`: list-type sections (Reminders, Maintenance) — always
    //    shows a "+" so the user can add more.
    //  - `editHeader`: single-record sections (Registration, Insurance) —
    //    only shows a pencil when there's data to edit; otherwise the empty
    //    state IS the entry point.
    //  - `emptySectionRow`: consistent inline empty-state button used inside
    //    a Section body when there are no records yet.

    private func addHeader(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle.fill").font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(title.lowercased())")
        }
    }

    private func editHeader(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) {
                Image(systemName: "pencil.circle.fill").font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(title.lowercased())")
        }
    }

    private func emptySectionRow(_ title: String, systemImage: String = "plus.circle", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundColor(.accentColor)
        }
    }

    // MARK: - Registration (own only — contains private fields)

    private var registrationSection: some View {
        let hasData = liveCar.map { !$0.licensePlate.isEmpty || !$0.vinNumber.isEmpty || $0.registrationExpiryDate != nil } ?? false

        return Section(header: sectionHeader(title: "Registration & Identification", hasData: hasData, edit: { showingEditRegistration = true })) {
            if let car = liveCar, hasData {
                if !car.licensePlate.isEmpty { DetailRow(label: "License Plate", value: car.licensePlate) }
                if !car.vinNumber.isEmpty { DetailRow(label: "VIN Number", value: car.vinNumber) }
                if let regDate = car.registrationExpiryDate {
                    ExpiryRow(
                        label: "Registration Expires",
                        date: regDate,
                        isExpired: car.isRegistrationExpired,
                        isExpiringSoon: car.isRegistrationExpiringSoon
                    )
                }
            } else {
                emptySectionRow("Add License Plate & VIN") { showingEditRegistration = true }
            }
        }
    }

    // Section header that swaps between plain title (empty) and title-with-edit
    // (populated). Used by both single-record sections below.
    @ViewBuilder
    private func sectionHeader(title: String, hasData: Bool, edit: @escaping () -> Void) -> some View {
        if hasData {
            editHeader(title, action: edit)
        } else {
            Text(title)
        }
    }

    // MARK: - Vehicle Details (own — has empty-state CTA)

    private var vehicleDetailsSection: some View {
        let hasData = liveCar.map(hasVehicleDetailsData) ?? false

        return Section(header: sectionHeader(title: "Vehicle Details", hasData: hasData, edit: { showingEditVehicleDetails = true })) {
            if let car = liveCar, hasData {
                if !car.color.isEmpty        { DetailRow(label: "Color", value: car.color) }
                if !car.mileage.isEmpty      { DetailRow(label: "Mileage", value: car.mileage) }
                if !car.fuelType.isEmpty     { DetailRow(label: "Fuel Type", value: car.fuelType) }
                if !car.transmission.isEmpty { DetailRow(label: "Transmission", value: car.transmission) }
                if !car.trim.isEmpty         { DetailRow(label: "Trim", value: car.trim) }
                if !car.bodyStyle.isEmpty    { DetailRow(label: "Body Style", value: car.bodyStyle) }
                if !car.driveType.isEmpty    { DetailRow(label: "Drive Type", value: car.driveType) }
                if !car.engine.isEmpty       { DetailRow(label: "Engine", value: car.engine) }
            } else {
                emptySectionRow("Add Vehicle Details") { showingEditVehicleDetails = true }
            }
        }
    }

    private func hasVehicleDetailsData(_ car: Car) -> Bool {
        !car.color.isEmpty || !car.mileage.isEmpty || !car.fuelType.isEmpty ||
            !car.transmission.isEmpty || !car.trim.isEmpty || !car.bodyStyle.isEmpty ||
            !car.driveType.isEmpty || !car.engine.isEmpty
    }

    // MARK: - Vehicle Details (public — includes trim/body/drive/engine)

    private var publicVehicleDetailsSection: some View {
        Section(header: Text("Vehicle Details")) {
            if !color.isEmpty       { DetailRow(label: "Color", value: color) }
            if !mileage.isEmpty     { DetailRow(label: "Mileage", value: mileage) }
            if !trim.isEmpty        { DetailRow(label: "Trim", value: trim) }
            if !bodyStyle.isEmpty   { DetailRow(label: "Body Style", value: bodyStyle) }
            if !driveType.isEmpty   { DetailRow(label: "Drive Type", value: driveType) }
            if !engine.isEmpty      { DetailRow(label: "Engine", value: engine) }
            if !fuelType.isEmpty    { DetailRow(label: "Fuel Type", value: fuelType) }
            if !transmission.isEmpty { DetailRow(label: "Transmission", value: transmission) }
        }
    }

    // MARK: - Insurance (own only — private fields)

    private var insuranceSection: some View {
        let hasData = liveCar.map { !$0.insuranceProvider.isEmpty || !$0.insurancePolicyNumber.isEmpty || $0.insuranceExpiryDate != nil } ?? false

        return Section(header: sectionHeader(title: "Insurance", hasData: hasData, edit: { showingEditInsurance = true })) {
            if let car = liveCar, hasData {
                if !car.insuranceProvider.isEmpty { DetailRow(label: "Provider", value: car.insuranceProvider) }
                if !car.insurancePolicyNumber.isEmpty { DetailRow(label: "Policy Number", value: car.insurancePolicyNumber) }
                if let insDate = car.insuranceExpiryDate {
                    ExpiryRow(
                        label: "Insurance Expires",
                        date: insDate,
                        isExpired: car.isInsuranceExpired,
                        isExpiringSoon: car.isInsuranceExpiringSoon
                    )
                }
            } else {
                emptySectionRow("Add Insurance Info") { showingEditInsurance = true }
            }
        }
    }

    // MARK: - Expense Summary (own only)

    private func expenseSummarySection(for car: Car) -> some View {
        Section(header: Text("Expense Summary")) {
            HStack {
                Text("Total Spent").foregroundColor(.secondary)
                Spacer()
                Text(formatCurrency(car.totalExpenses)).fontWeight(.semibold)
            }
            ForEach(car.expensesByCategory(in: .allTime), id: \.category) { item in
                HStack {
                    Text(item.category).font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text(formatCurrency(item.amount)).font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    // MARK: - Reminders (own only)

    private var remindersSection: some View {
        Section(header: addHeader("Service Reminders") { showingAddReminder = true }) {
            if let car = liveCar {
                let upcoming = car.serviceReminders.filter { !$0.isCompleted }
                let currentMileage = ServiceReminderEngine.mileage(from: car.mileage)
                let overdueCount = upcoming.filter { $0.status(currentMileage: currentMileage) == .overdue }.count

                if upcoming.isEmpty && car.serviceReminders.isEmpty {
                    emptySectionRow("Add Reminder", systemImage: "wrench.and.screwdriver") {
                        showingAddReminder = true
                    }
                } else {
                    NavigationLink(destination: ServiceRemindersView(carID: car.id)) {
                        HStack {
                            Image(systemName: overdueCount > 0 ? "exclamationmark.circle.fill" : "wrench.and.screwdriver")
                                .foregroundColor(overdueCount > 0 ? .red : .accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(upcoming.isEmpty ? "\(car.serviceReminders.count) Completed" : "\(upcoming.count) Upcoming")
                                    .font(.subheadline)
                                if overdueCount > 0 {
                                    Text("\(overdueCount) overdue").font(.caption).foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Maintenance (own — editable with costs)

    private var maintenanceSection: some View {
        Section(header: addHeader("Maintenance Log") { showingAddMaintenance = true }) {
            if let car = liveCar {
                if car.sortedMaintenanceRecords.isEmpty {
                    emptySectionRow("Add Service Record", systemImage: "wrench.and.screwdriver") {
                        showingAddMaintenance = true
                    }
                } else {
                    ForEach(car.sortedMaintenanceRecords) { record in
                        MaintenanceRowView(record: record)
                    }
                    .onDelete { offsets in
                        let sorted = car.sortedMaintenanceRecords
                        for index in offsets where index < sorted.count {
                            carStore.deleteMaintenanceRecord(sorted[index], from: car)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Service History (public — no costs)

    private func publicServiceHistorySection(for pc: PublicCar) -> some View {
        Section(header: HStack {
            Text("Service History")
            Spacer()
            Text("\(pc.serviceHistory.count) records")
                .font(.caption).foregroundColor(.secondary)
        }) {
            ForEach(pc.serviceHistory.sorted { $0.date > $1.date }.prefix(5)) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.serviceType)
                        .font(.subheadline).fontWeight(.medium)
                    Text(record.date, style: .date)
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Delete Car (own only)

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Delete Car", systemImage: "trash")
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct GalleryStart: Identifiable {
    let index: Int
    var id: Int { index }
}

struct ExpiryBannerItem: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color).font(.subheadline)
            Text(text).font(.subheadline).fontWeight(.medium).foregroundColor(color)
        }
    }
}

struct ExpiryRow: View {
    let label: String
    let date: Date
    let isExpired: Bool
    let isExpiringSoon: Bool

    private var statusColor: Color {
        if isExpired { return .red }
        if isExpiringSoon { return .orange }
        return .primary
    }

    private var daysText: String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return "Expired" }
        if days == 0 { return "Expires today" }
        if days == 1 { return "Expires tomorrow" }
        return "Expires in \(days) days"
    }

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(date, style: .date).foregroundColor(statusColor)
                if isExpired || isExpiringSoon {
                    Text(daysText).font(.caption).fontWeight(.medium).foregroundColor(statusColor)
                }
            }
        }
    }
}

struct MaintenanceRowView: View {
    let record: MaintenanceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.serviceType).font(.subheadline).fontWeight(.medium)
                Spacer()
                if !record.cost.isEmpty {
                    Text("$\(record.cost)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
            }

            HStack(spacing: 12) {
                Text(record.date, style: .date).font(.caption).foregroundColor(.secondary)
                if !record.mileage.isEmpty {
                    Text("\(record.mileage) mi").font(.caption).foregroundColor(.secondary)
                }
                if !record.shop.isEmpty {
                    Text(record.shop).font(.caption).foregroundColor(.secondary)
                }
            }

            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.caption).foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .foregroundColor(value.isEmpty ? .secondary.opacity(0.5) : .primary)
        }
    }
}

// MARK: - Focused-edit presenter cluster
//
// Wraps the three per-section focused sheets (Registration, Insurance, Add
// Reminder) into a single modifier so CarDetailView.body's trailing chain
// stays cheap for the SwiftUI type checker. Same technique we used in
// EditCarDetailView after the "unable to type-check in reasonable time"
// error surfaced there.
private struct FocusedEditPresenters: ViewModifier {
    let liveCar: Car?
    @Binding var showingEditRegistration: Bool
    @Binding var showingEditVehicleDetails: Bool
    @Binding var showingEditInsurance: Bool
    @Binding var showingAddReminder: Bool
    let onSave: (Car) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingEditRegistration) {
                if let car = liveCar {
                    EditRegistrationSheet(car: car, onSave: onSave)
                }
            }
            .sheet(isPresented: $showingEditVehicleDetails) {
                if let car = liveCar {
                    EditVehicleDetailsSheet(car: car, onSave: onSave)
                }
            }
            .sheet(isPresented: $showingEditInsurance) {
                if let car = liveCar {
                    EditInsuranceSheet(car: car, onSave: onSave)
                }
            }
            .sheet(isPresented: $showingAddReminder) {
                if let car = liveCar {
                    AddReminderView(carID: car.id)
                }
            }
    }
}
