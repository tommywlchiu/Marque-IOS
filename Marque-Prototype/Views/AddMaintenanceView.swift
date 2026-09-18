import SwiftUI
import VisionKit

struct AddMaintenanceView: View {
    @Environment(\.dismiss) var dismiss

    var onSave: (MaintenanceRecord) -> Void

    @State private var serviceType = ""
    @State private var date = Date()
    @State private var mileage = ""
    @State private var cost = ""
    @State private var shop = ""
    @State private var notes = ""

    // MARK: - Receipt scan state

    @State private var showingReceiptScanner = false
    @State private var isScanningReceipt = false
    @State private var scanResult: ReceiptScanPreview?
    @State private var scanError: DocumentScanService.ScanError?

    private let scanService = DocumentScanService()
    @EnvironmentObject private var scanAllowance: ScanAllowanceStore
    @State private var showingScanPaywall = false

    fileprivate struct ReceiptScanPreview: Identifiable {
        let id = UUID()
        let serviceType: String
        let date: Date?
        let mileage: String
        let cost: String
        let shop: String
        let description: String
    }

    var isFormValid: Bool {
        !serviceType.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Quick Fill")) {
                    scanReceiptRow
                }

                Section(header: Text("Service")) {
                    Picker("Service Type", selection: $serviceType) {
                        Text("Select a service").tag("")
                        ForEach(MaintenanceRecord.serviceTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section(header: Text("Details")) {
                    TextField("Mileage at service", text: $mileage)
                        .keyboardType(.numberPad)

                    HStack {
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("Cost", text: $cost)
                            .keyboardType(.decimalPad)
                    }

                    TextField("Shop / Mechanic", text: $shop)
                }

                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add Service Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let record = MaintenanceRecord(
                            serviceType: serviceType,
                            date: date,
                            mileage: mileage.trimmingCharacters(in: .whitespaces),
                            cost: cost.trimmingCharacters(in: .whitespaces),
                            shop: shop.trimmingCharacters(in: .whitespaces),
                            notes: notes.trimmingCharacters(in: .whitespaces)
                        )
                        onSave(record)
                        dismiss()
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
            .fullScreenCover(isPresented: $showingReceiptScanner) {
                DocumentScannerView(
                    onScan: { image in
                        showingReceiptScanner = false
                        Task { await processReceiptScan(image) }
                    },
                    onCancel: { showingReceiptScanner = false },
                    onError: { error in
                        showingReceiptScanner = false
                        scanError = .unknown(error.localizedDescription)
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $scanResult) { result in
                ReceiptScanConfirmationSheet(
                    result: result,
                    onUse: { applyReceiptScan(result) }
                )
            }
            .alert(
                scanError?.alertTitle ?? "Scan Failed",
                isPresented: Binding(
                    get: { scanError != nil },
                    set: { if !$0 { scanError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanError?.errorDescription ?? "")
            }
        }
    }

    // MARK: - Receipt scan

    private var scanReceiptRow: some View {
        Button {
            if VNDocumentCameraViewController.isSupported {
                if scanAllowance.canStartScan() {
                    showingReceiptScanner = true
                } else {
                    showingScanPaywall = true
                }
            } else {
                scanError = .cameraUnsupported
            }
        } label: {
            HStack {
                Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                Spacer()
                if isScanningReceipt {
                    ProgressView()
                } else {
                    ScanAllowanceCaption()
                }
            }
        }
        .disabled(isScanningReceipt)
        .scanCapPaywall(isPresented: $showingScanPaywall)
    }

    private func processReceiptScan(_ image: UIImage) async {
        isScanningReceipt = true
        scanError = nil
        defer { isScanningReceipt = false }

        do {
            let result = try await scanService.scanMaintenanceReceipt(image: image)
            scanResult = ReceiptScanPreview(
                serviceType: result.serviceType,
                date: result.date,
                mileage: result.mileage,
                cost: result.cost,
                shop: result.shop,
                description: result.description
            )
        } catch let error as DocumentScanService.ScanError {
            scanError = error
        } catch {
            scanError = .unknown(error.localizedDescription)
        }
    }

    // Merge-in policy: only overwrite a form field when the scan returned a
    // non-empty value for it. Description is appended to notes rather than
    // clobbering user-typed notes.
    private func applyReceiptScan(_ result: ReceiptScanPreview) {
        if !result.serviceType.isEmpty {
            // The picker only displays values that match one of the preset tags.
            // Try to snap the scanned type to a preset (case-insensitive substring
            // either way — "Full synthetic oil change" → "Oil Change"). Fall back
            // to "Other" so the picker renders a valid selection, and record the
            // raw scanned type in notes so the info isn't lost.
            let normalized = normalizeServiceType(result.serviceType)
            serviceType = normalized.tag
            if let raw = normalized.rawIfUnmatched {
                appendToNotes("Service: \(raw)")
            }
        }
        if let scanDate = result.date {
            date = scanDate
        }
        if !result.mileage.isEmpty {
            // Strip commas so it keys correctly into the numberPad-driven field.
            mileage = result.mileage.replacingOccurrences(of: ",", with: "")
        }
        if !result.cost.isEmpty {
            // Strip $ and commas so it fits the decimalPad-driven field.
            cost = result.cost
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        if !result.shop.isEmpty {
            shop = result.shop
        }
        if !result.description.isEmpty {
            appendToNotes(result.description)
        }
    }

    private func normalizeServiceType(_ raw: String) -> (tag: String, rawIfUnmatched: String?) {
        let presets = MaintenanceRecord.serviceTypes
        // Exact match first (case-insensitive).
        if let exact = presets.first(where: { $0.caseInsensitiveCompare(raw) == .orderedSame }) {
            return (exact, nil)
        }
        // Substring match: preset name appears anywhere in the scan (e.g., "Full
        // synthetic oil change" contains "Oil Change"). "Other" is skipped so it
        // remains the last-resort fallback.
        let searchable = presets.filter { $0 != "Other" }
        if let match = searchable.first(where: { raw.localizedCaseInsensitiveContains($0) }) {
            return (match, nil)
        }
        // No match — fall back to "Other" and preserve the raw label in notes.
        return ("Other", raw)
    }

    private func appendToNotes(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if notes.isEmpty {
            notes = trimmed
        } else {
            notes += "\n\n" + trimmed
        }
    }
}

// MARK: - Receipt scan confirmation sheet

private struct ReceiptScanConfirmationSheet: View {
    let result: AddMaintenanceView.ReceiptScanPreview
    let onUse: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Review what we found, then tap Use These to fill in the form. You can edit anything before saving.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Extracted") {
                    LabeledContent("Service", value: displayValue(result.serviceType))
                    LabeledContent("Date", value: displayDate(result.date))
                    LabeledContent("Mileage", value: displayValue(result.mileage))
                    LabeledContent("Cost", value: displayCost(result.cost))
                    LabeledContent("Shop", value: displayValue(result.shop))
                }

                if !result.description.isEmpty {
                    Section("Details") {
                        Text(result.description)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use These") {
                        onUse()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasAnyValue)
                }
            }
        }
    }

    private var hasAnyValue: Bool {
        !result.serviceType.isEmpty || result.date != nil
            || !result.mileage.isEmpty || !result.cost.isEmpty
            || !result.shop.isEmpty || !result.description.isEmpty
    }

    private func displayValue(_ s: String) -> String {
        s.isEmpty ? "—" : s
    }

    private func displayDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func displayCost(_ s: String) -> String {
        s.isEmpty ? "—" : "$\(s)"
    }
}
