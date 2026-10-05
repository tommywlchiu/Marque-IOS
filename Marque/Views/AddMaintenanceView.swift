import SwiftUI
import VisionKit
import PhotosUI

/// Add-or-edit form for a `MaintenanceRecord`. Two entry points:
///  - `init(prefill:onSkip:onSave:)` — Add mode. `prefill` (service type / date /
///    mileage) is set when this is opened from checking off a matching
///    `ServiceReminder`; `onSkip`, present only in that case, marks the
///    reminder done without logging a record ("Skip — just mark done").
///  - `init(record:onSave:onDelete:)` — Edit mode for an existing record, with
///    a Delete button.
/// Callers are responsible for the actual `CarStore` write (`logService` /
/// `updateMaintenanceRecord` / `deleteMaintenanceRecord`) — this view only
/// hands back the built `MaintenanceRecord` plus any receipt image change.
struct AddMaintenanceView: View {
    @Environment(\.dismiss) var dismiss

    struct Prefill {
        let serviceType: String
        let date: Date
        let mileage: String
    }

    private let editingRecord: MaintenanceRecord?
    private let onSaveAdd: ((MaintenanceRecord, UIImage?) -> Void)?
    private let onSaveEdit: ((MaintenanceRecord, UIImage?, _ removeReceipt: Bool) -> Void)?
    private let onSkip: (() -> Void)?
    private let onDelete: (() -> Void)?

    @State private var serviceType = ""
    @State private var customServiceType = ""
    @State private var date = Date()
    @State private var mileage = ""
    @State private var cost = ""
    @State private var shop = ""
    @State private var notes = ""

    // MARK: - Receipt attachment
    //
    // `receiptImage` is a freshly attached/replacement image from this
    // session (scan, library pick, or a re-scan while editing). The
    // `existing*` pair mirrors an edit-mode record's already-saved receipt so
    // it can be previewed and removed without re-attaching anything.
    // `removeExistingReceipt` is the edit-mode "take it off" flag threaded
    // through to `CarStore.updateMaintenanceRecord`.
    @State private var receiptImage: UIImage?
    @State private var existingReceiptFileName: String?
    @State private var existingReceiptStorageURL: String?
    @State private var removeExistingReceipt = false
    @State private var showingReceiptViewer = false
    @State private var selectedLibraryItem: PhotosPickerItem?

    @State private var showingDeleteConfirmation = false

    // MARK: - Receipt scan (OCR) state

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
        // Kept so "Use These" can also attach the scanned photo itself as
        // the record's receipt, not just its OCR'd fields.
        let image: UIImage
    }

    private var isEditing: Bool { editingRecord != nil }

    // MARK: - Init

    /// Add mode.
    init(
        prefill: Prefill? = nil,
        onSkip: (() -> Void)? = nil,
        onSave: @escaping (MaintenanceRecord, UIImage?) -> Void
    ) {
        self.editingRecord = nil
        self.onSaveAdd = onSave
        self.onSaveEdit = nil
        self.onSkip = onSkip
        self.onDelete = nil

        if let prefill {
            let isPreset = MaintenanceRecord.serviceTypes.contains(prefill.serviceType)
            _serviceType = State(initialValue: isPreset ? prefill.serviceType : "Other")
            _customServiceType = State(initialValue: isPreset ? "" : prefill.serviceType)
            _date = State(initialValue: prefill.date)
            _mileage = State(initialValue: prefill.mileage)
        }
    }

    /// Edit mode.
    init(
        record: MaintenanceRecord,
        onSave: @escaping (MaintenanceRecord, UIImage?, _ removeReceipt: Bool) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.editingRecord = record
        self.onSaveAdd = nil
        self.onSaveEdit = onSave
        self.onSkip = nil
        self.onDelete = onDelete

        let isPreset = MaintenanceRecord.serviceTypes.contains(record.serviceType)
        _serviceType = State(initialValue: isPreset ? record.serviceType : "Other")
        _customServiceType = State(initialValue: isPreset ? "" : record.serviceType)
        _date = State(initialValue: record.date)
        _mileage = State(initialValue: record.mileage)
        _cost = State(initialValue: record.cost)
        _shop = State(initialValue: record.shop)
        _notes = State(initialValue: record.notes)
        _existingReceiptFileName = State(initialValue: record.receiptFileName)
        _existingReceiptStorageURL = State(initialValue: record.receiptStorageURL)
    }

    // "Other" gets a custom-name field; that name is what actually gets saved.
    private var resolvedServiceType: String {
        serviceType == "Other" ? customServiceType.trimmingCharacters(in: .whitespaces) : serviceType
    }

    var isFormValid: Bool {
        !resolvedServiceType.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                skipSection

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

                    if serviceType == "Other" {
                        TextField("Service name", text: $customServiceType)
                            .autocorrectionDisabled()
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

                receiptSection

                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                deleteSection
            }
            .navigationTitle(isEditing ? "Edit Service Record" : "Add Service Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        save()
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
            .fullScreenCover(isPresented: $showingReceiptViewer) {
                ReceiptFullScreenView(image: displayedReceiptImage, remoteURL: displayedReceiptRemoteURL)
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
            .alert("Delete Service Record", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("This will permanently delete this service record. This cannot be undone.")
            }
            .onChange(of: selectedLibraryItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run { attachReceipt(image) }
                    }
                    await MainActor.run { selectedLibraryItem = nil }
                }
            }
        }
    }

    // MARK: - Skip (only when opened from a reminder check-off)

    @ViewBuilder
    private var skipSection: some View {
        if let onSkip {
            Section {
                Button {
                    onSkip()
                    dismiss()
                } label: {
                    Label("Skip — just mark done", systemImage: "checkmark.circle")
                }
            } footer: {
                Text("Marks this reminder complete without logging a service record.")
            }
        }
    }

    // MARK: - Delete (edit mode only)

    @ViewBuilder
    private var deleteSection: some View {
        if isEditing {
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Record", systemImage: "trash")
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let record = MaintenanceRecord(
            id: editingRecord?.id ?? UUID(),
            serviceType: resolvedServiceType,
            date: date,
            mileage: mileage.trimmingCharacters(in: .whitespaces),
            cost: cost.trimmingCharacters(in: .whitespaces),
            shop: shop.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces),
            // Baseline receipt fields — the store overwrites these when a new
            // image or a removal is supplied, so an untouched receipt must be
            // carried through unchanged here rather than dropped.
            receiptFileName: editingRecord?.receiptFileName,
            receiptStorageURL: editingRecord?.receiptStorageURL
        )

        if isEditing {
            onSaveEdit?(record, receiptImage, removeExistingReceipt)
        } else {
            onSaveAdd?(record, receiptImage)
        }
        dismiss()
    }

    // MARK: - Receipt attach/remove/display

    private func attachReceipt(_ image: UIImage) {
        receiptImage = image
        removeExistingReceipt = false
    }

    private func removeReceipt() {
        receiptImage = nil
        removeExistingReceipt = true
    }

    private var displayedReceiptImage: UIImage? {
        if let receiptImage { return receiptImage }
        guard !removeExistingReceipt, let fileName = existingReceiptFileName else { return nil }
        return ImageManager.loadImage(fileName: fileName)
    }

    private var displayedReceiptRemoteURL: URL? {
        guard !removeExistingReceipt, displayedReceiptImage == nil,
              let s = existingReceiptStorageURL, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var hasReceipt: Bool {
        displayedReceiptImage != nil || displayedReceiptRemoteURL != nil
    }

    private var receiptSection: some View {
        Section(header: Text("Receipt")) {
            if hasReceipt {
                Button {
                    showingReceiptViewer = true
                } label: {
                    HStack(spacing: 12) {
                        receiptThumbnail
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("View Receipt")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    removeReceipt()
                } label: {
                    Label("Remove Receipt", systemImage: "trash")
                }
            } else {
                PhotosPicker(selection: $selectedLibraryItem, matching: .images) {
                    Label("Attach from Photo Library", systemImage: "photo.on.rectangle")
                }
            }
        }
    }

    @ViewBuilder
    private var receiptThumbnail: some View {
        if let image = displayedReceiptImage {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let url = displayedReceiptRemoteURL {
            CachedRemoteImage(url: url)
        } else {
            Color(.systemGray5)
        }
    }

    // MARK: - Receipt scan (OCR)

    private var scanReceiptRow: some View {
        Button {
            startReceiptScan()
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

    private func startReceiptScan() {
        if VNDocumentCameraViewController.isSupported {
            if scanAllowance.canStartScan() {
                showingReceiptScanner = true
            } else {
                showingScanPaywall = true
            }
        } else {
            scanError = .cameraUnsupported
        }
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
                description: result.description,
                image: image
            )
            // Light success touch the moment OCR data comes back — no sound,
            // no confetti, just a confirming tap.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let error as DocumentScanService.ScanError {
            scanError = error
        } catch {
            scanError = .unknown(error.localizedDescription)
        }
    }

    // Merge-in policy: only overwrite a form field when the scan returned a
    // non-empty value for it. Description is appended to notes rather than
    // clobbering user-typed notes. The scanned photo itself is always
    // attached as the receipt.
    private func applyReceiptScan(_ result: ReceiptScanPreview) {
        if !result.serviceType.isEmpty {
            // The picker only displays values that match one of the preset tags.
            // Try to snap the scanned type to a preset (case-insensitive substring
            // either way — "Full synthetic oil change" → "Oil Change"). Fall back
            // to "Other" so the picker renders a valid selection, and record the
            // raw scanned type in notes so the info isn't lost.
            let normalized = normalizeServiceType(result.serviceType)
            serviceType = normalized.tag
            if normalized.tag == "Other" {
                customServiceType = result.serviceType
            }
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
        attachReceipt(result.image)
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

// MARK: - Receipt full-screen viewer

private struct ReceiptFullScreenView: View {
    let image: UIImage?
    let remoteURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if let remoteURL {
                    CachedRemoteImage(url: remoteURL)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.black
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(.white)
                }
            }
        }
    }
}

// MARK: - Receipt scan confirmation sheet

private struct ReceiptScanConfirmationSheet: View {
    let result: AddMaintenanceView.ReceiptScanPreview
    let onUse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var checkmarkVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.green)
                            .scaleEffect(checkmarkVisible ? 1.0 : 0.6)
                            .opacity(checkmarkVisible ? 1.0 : 0.0)
                            .onAppear {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                    checkmarkVisible = true
                                }
                            }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

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
