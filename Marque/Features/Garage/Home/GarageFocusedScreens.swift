import SwiftUI

/// Everything the Garage home pushes onto its NavigationStack.
enum GarageRoute: Hashable {
    case serviceHistory(UUID)
    case reminders(UUID)
    case mods(UUID)
    case expenses(UUID)
    case value(UUID)
    case engineSound(UUID)
    case publicSharing(UUID)
    case details(UUID)
    case customize(UUID)
    /// Public Sharing with the comments sheet open (a comment notification).
    case carComments(UUID)
}

/// Shell for a focused screen about one car: resolves the live car from
/// `CarStore` (so edits and listener updates flow in), handles a car deleted
/// while the screen is open, and applies the Garage chrome.
struct GarageCarScreen<Content: View>: View {
    let carID: UUID
    let title: String
    @ViewBuilder let content: (Car) -> Content

    @EnvironmentObject private var carStore: CarStore

    var body: some View {
        Group {
            if let car = carStore.cars.first(where: { $0.id == carID }) {
                content(car)
            } else {
                MarqueEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Car not found",
                    subtitle: "This car may have been deleted."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .garageScreenChrome()
    }
}

// MARK: - Service History

struct GarageServiceHistoryScreen: View {
    let carID: UUID

    @State private var addRequest: MaintenanceAddRequest?
    @State private var editingRecord: MaintenanceRecord?
    @State private var logConfirmation: LogConfirmation?

    var body: some View {
        GarageCarScreen(carID: carID, title: "Service History") { car in
            List {
                MaintenanceLogSection(
                    car: car,
                    onAdd: { addRequest = MaintenanceAddRequest() },
                    onEdit: { editingRecord = $0 }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addRequest = MaintenanceAddRequest() } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add service record")
            }
        }
        .modifier(MaintenanceLogFlow(
            carID: carID,
            addRequest: $addRequest,
            editingRecord: $editingRecord,
            logConfirmation: $logConfirmation
        ))
        .modifier(LogConfirmationOverlay(carID: carID, confirmation: $logConfirmation))
    }
}

// MARK: - Mods / Value / Engine Sound (self-contained sections)

struct GarageModsScreen: View {
    let carID: UUID

    var body: some View {
        GarageCarScreen(carID: carID, title: "Mods") { car in
            List {
                CarModsSection(car: car)
                    .garageRowBackground()
            }
        }
    }
}

struct GarageValueScreen: View {
    let carID: UUID

    var body: some View {
        GarageCarScreen(carID: carID, title: "Estimated Value") { car in
            List {
                CarValueSection(car: car)
                    .garageRowBackground()
            }
        }
    }
}

struct GarageEngineSoundScreen: View {
    let carID: UUID

    var body: some View {
        GarageCarScreen(carID: carID, title: "Engine Sound") { car in
            List {
                EngineSoundOwnerSection(car: car)
                    .garageRowBackground()
            }
        }
    }
}

// MARK: - Expenses

struct GarageExpensesScreen: View {
    let carID: UUID

    var body: some View {
        GarageCarScreen(carID: carID, title: "Expenses") { car in
            List {
                if car.totalExpenses > 0 {
                    ExpenseSummarySection(car: car)
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No expenses yet")
                                .font(.headline)
                            Text("Log a service with a cost and it shows up here.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .garageRowBackground()
                }

                Section {
                    // ExpenseChartsView covers every car in the garage.
                    NavigationLink {
                        ExpenseChartsView()
                    } label: {
                        Label("Insights across all your cars", systemImage: "chart.bar.xaxis")
                    }
                }
                .garageRowBackground()
            }
        }
    }
}

// MARK: - Public Sharing

struct GaragePublicSharingScreen: View {
    let carID: UUID
    var openCommentsOnAppear = false

    @EnvironmentObject private var carStore: CarStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var exploreStore: ExploreStore

    @State private var showingSharingSheet = false
    @State private var sharingSheetMode: PublicSharingSheetMode = .goingPublic
    @State private var showingMakePrivateConfirmation = false
    @State private var showingPushPrePrompt = false
    @State private var commentsRequest: CommentsSheetRequest?
    // CarSocialPresenters also drives these; nothing on this screen sets them.
    @State private var reportTarget: CarReportTarget?
    @State private var commentActionError: String?
    @State private var blockTarget: UserRef?
    @State private var profileTarget: UserRef?
    @State private var didOpenComments = false

    private var liveCar: Car? { carStore.cars.first(where: { $0.id == carID }) }

    var body: some View {
        GarageCarScreen(carID: carID, title: "Public Sharing") { car in
            List {
                CarVisibilitySection(
                    car: car,
                    onRequestPublic: {
                        sharingSheetMode = .goingPublic
                        showingSharingSheet = true
                    },
                    onRequestPrivate: { showingMakePrivateConfirmation = true },
                    onEditSharing: {
                        sharingSheetMode = .editing
                        showingSharingSheet = true
                    }
                ) {
                    let published = OwnCarPublicProjection.publishedCopy(of: car, in: exploreStore)
                    OwnCarEngagementRow(
                        publicCar: published,
                        commentCount: published?.commentCount ?? 0,
                        onOpenComments: { openComments(for: car) }
                    )
                }
            }
            .modifier(CommentsListenerLifecycle(carId: car.isPublic ? car.id.uuidString : nil))
            .onAppear {
                guard openCommentsOnAppear, !didOpenComments, car.isPublic else { return }
                didOpenComments = true
                openComments(for: car)
            }
        }
        .modifier(PublicSharingSheetPresenter(
            car: liveCar,
            mode: sharingSheetMode,
            isPresented: $showingSharingSheet,
            onMadePublic: { PushPrePrompt.offer { showingPushPrePrompt = true } }
        ))
        .modifier(CarSocialPresenters(
            commentsRequest: $commentsRequest,
            reportTarget: $reportTarget,
            showingPushPrePrompt: $showingPushPrePrompt,
            showingMakePrivateConfirmation: $showingMakePrivateConfirmation,
            commentActionError: $commentActionError,
            blockTarget: $blockTarget,
            profileTarget: $profileTarget,
            onConfirmMakePrivate: {
                guard let car = liveCar else { return }
                CarVisibilityActions.apply(false, to: car, carStore: carStore, authService: authService)
            }
        ))
    }

    private func openComments(for car: Car) {
        commentsRequest = CommentsSheetRequest(
            carId: car.id.uuidString,
            carOwnerUID: authService.currentUser?.id ?? "",
            carName: car.displayName,
            focusComposer: false
        )
    }
}

// MARK: - Details

struct GarageDetailsScreen: View {
    let carID: UUID

    @EnvironmentObject private var carStore: CarStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditVehicleDetails = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        GarageCarScreen(carID: carID, title: "Details") { car in
            List {
                BasicInfoSection(make: car.make, model: car.model, year: car.year)
                VehicleDetailsSection(specs: VehicleSpecs(car: car)) { showingEditVehicleDetails = true }
                if !car.notes.isEmpty {
                    Section(header: Text("Notes")) {
                        Text(car.notes).font(.body)
                    }
                    .garageRowBackground()
                }
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
                .garageRowBackground()
            }
            .sheet(isPresented: $showingEditVehicleDetails) {
                EditVehicleDetailsSheet(car: car) { carStore.updateCar($0) }
            }
            .alert("Delete Car", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    carStore.deleteCar(car)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete \(car.displayName)? This action cannot be undone.")
            }
        }
    }
}

// MARK: - Customize

/// How the car's studio render is dressed in the Garage hero: window tint
/// now; the license plate shown here is edited where it lives (Wallet ›
/// Registration). Private — none of it reaches Explore.
struct GarageCustomizeScreen: View {
    let carID: UUID

    @EnvironmentObject private var carStore: CarStore
    @Environment(\.selectMainTab) private var selectMainTab

    var body: some View {
        GarageCarScreen(carID: carID, title: "Customize") { car in
            List {
                Section {
                    GarageHeroView(car: car, height: 220)
                        .listRowInsets(EdgeInsets())
                }
                .garageRowBackground()

                Section(header: Text("Window Tint")) {
                    Picker("Window Tint", selection: Binding(
                        get: { car.customization.tint },
                        set: { tint in
                            var updated = car
                            updated.customization.tint = tint
                            carStore.updateCar(updated)
                        }
                    )) {
                        ForEach(CarCustomization.Tint.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .garageRowBackground()

                if CarRenderLibrary.match(car, in: CarRenderLibrary.cachedCatalog())?.canChangeStance == true {
                    Section(header: Text("Stance")) {
                        Picker("Stance", selection: Binding(
                            get: { car.customization.stance },
                            set: { stance in
                                var updated = car
                                updated.customization.stance = stance
                                carStore.updateCar(updated)
                            }
                        )) {
                            ForEach(CarCustomization.Stance.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .garageRowBackground()
                }

                let styles = wheelStyles(for: car)
                if !styles.isEmpty {
                    Section(header: Text("Wheels")) {
                        wheelRow(car, id: nil, title: "Stock")
                        ForEach(styles) { wheelRow(car, id: $0.id, title: $0.title) }
                    }
                    .garageRowBackground()
                }

                Section(header: Text("License Plate"),
                        footer: Text("Shown on your car in your Garage only — never in Explore.")) {
                    HStack {
                        Text(car.licensePlate.isEmpty ? "No plate on file" : car.licensePlate)
                            .foregroundColor(car.licensePlate.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button("Edit in Wallet") { selectMainTab(.wallet) }
                    }
                }
                .garageRowBackground()
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// The wheel styles rendered for this car, in the catalog's order.
    private func wheelStyles(for car: Car) -> [CarRenderLibrary.WheelStyle] {
        let catalog = CarRenderLibrary.cachedCatalog()
        guard let match = CarRenderLibrary.match(car, in: catalog) else { return [] }
        return (catalog?.wheelStyles ?? []).filter { match.wheelStyles.contains($0.id) }
    }

    private func wheelRow(_ car: Car, id: String?, title: String) -> some View {
        Button {
            var updated = car
            updated.customization.wheels = id
            carStore.updateCar(updated)
        } label: {
            HStack {
                Text(title).foregroundColor(.primary)
                Spacer()
                if car.customization.wheels == id {
                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                }
            }
        }
    }
}
