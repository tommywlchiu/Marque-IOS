import SwiftUI

// The owner's maintenance log, extracted from CarDetailView so the car page,
// the Garage's Service History screen and the Garage home quick actions all
// log, edit and undo through one implementation.

/// "Maintenance Log" list section: an empty-state row, or every record
/// newest-first (tap to edit, swipe to delete).
struct MaintenanceLogSection: View {
    let car: Car
    let onAdd: () -> Void
    let onEdit: (MaintenanceRecord) -> Void

    @EnvironmentObject private var carStore: CarStore

    var body: some View {
        Section(header: AddSectionHeader(title: "Maintenance Log", action: onAdd)) {
            if car.sortedMaintenanceRecords.isEmpty {
                EmptySectionRow(title: "Add Service Record", systemImage: "wrench.and.screwdriver", action: onAdd)
            } else {
                ForEach(car.sortedMaintenanceRecords) { record in
                    Button {
                        onEdit(record)
                    } label: {
                        HStack {
                            MaintenanceRowView(record: record)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let sorted = car.sortedMaintenanceRecords
                    for index in offsets where index < sorted.count {
                        carStore.deleteMaintenanceRecord(sorted[index], from: car)
                    }
                }
            }
        }
        .garageRowBackground()
    }
}

/// Opens the Add Service Record form. A fresh id per request so the same
/// kind of request twice in a row still presents.
struct MaintenanceAddRequest: Identifiable {
    let id = UUID()
    /// Open the receipt scanner immediately (the Garage "Scan" action).
    var startWithReceiptScan = false
}

/// The add/edit maintenance sheets, the record-limit alert, and the writes
/// behind them. Logging goes through `CarStore.logService`, which also
/// auto-completes matching reminders, schedules the next occurrence and bumps
/// mileage, then sets `logConfirmation` (rendered by
/// `LogConfirmationOverlay`) so the user can undo those side effects.
/// `logService` fires `maintenanceRecordAdded` itself.
struct MaintenanceLogFlow: ViewModifier {
    let carID: UUID
    @Binding var addRequest: MaintenanceAddRequest?
    @Binding var editingRecord: MaintenanceRecord?
    @Binding var logConfirmation: LogConfirmation?

    @EnvironmentObject private var carStore: CarStore
    @State private var showingLimitAlert = false

    /// Re-read at call time; a sheet may have been open a while.
    private var liveCar: Car? { carStore.cars.first(where: { $0.id == carID }) }

    func body(content: Content) -> some View {
        content
            .sheet(item: $addRequest) { request in
                AddMaintenanceView(startWithReceiptScan: request.startWithReceiptScan) { record, image in
                    logNewRecord(record, receiptImage: image)
                }
            }
            .sheet(item: $editingRecord) { record in
                AddMaintenanceView(
                    record: record,
                    onSave: { updated, image, removeReceipt in update(updated, image: image, removeReceipt: removeReceipt) },
                    onDelete: {
                        guard let car = liveCar else { return }
                        carStore.deleteMaintenanceRecord(record, from: car)
                    }
                )
            }
            .alert("Record Limit Reached", isPresented: $showingLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This car has reached the \(CarStore.maxMaintenanceRecords)-record limit. Delete an older record to add a new one.")
            }
    }

    private func logNewRecord(_ record: MaintenanceRecord, receiptImage: UIImage?) {
        guard let car = liveCar else { return }
        guard car.maintenanceRecords.count < CarStore.maxMaintenanceRecords else {
            showingLimitAlert = true
            return
        }
        let outcome = carStore.logService(record, for: car, receiptImage: receiptImage)
        let confirmation = LogConfirmation(logged: record, outcome: outcome)
        withAnimation { logConfirmation = confirmation }
        let binding = $logConfirmation
        Task {
            try? await Task.sleep(for: .seconds(5))
            if binding.wrappedValue?.id == confirmation.id {
                withAnimation { binding.wrappedValue = nil }
            }
        }
    }

    private func update(_ updated: MaintenanceRecord, image: UIImage?, removeReceipt: Bool) {
        guard let car = liveCar else { return }
        var updated = updated
        // The form holds the record as it was when opened. A receipt upload
        // that finished since then set receiptStorageURL on the live record;
        // keep it unless this save replaces or removes the receipt.
        if image == nil, !removeReceipt,
           let live = car.maintenanceRecords.first(where: { $0.id == updated.id }) {
            updated.receiptFileName = live.receiptFileName
            updated.receiptStorageURL = live.receiptStorageURL
        }
        carStore.updateMaintenanceRecord(updated, in: car, newReceiptImage: image, removeReceipt: removeReceipt)
    }
}

/// Bottom-edge "Oil Change logged · Reminder completed" banner with Undo.
struct LogConfirmationOverlay: ViewModifier {
    let carID: UUID
    @Binding var confirmation: LogConfirmation?

    @EnvironmentObject private var carStore: CarStore

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let confirmation {
                LogConfirmationBanner(message: confirmation.message) {
                    if let car = carStore.cars.first(where: { $0.id == carID }) {
                        carStore.undoLogSideEffects(confirmation.outcome, for: car)
                    }
                    withAnimation { self.confirmation = nil }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
