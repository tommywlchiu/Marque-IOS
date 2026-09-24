import SwiftUI
import VisionKit

// Focused sheet for editing just a car's insurance fields. Presented from the
// Insurance section of CarDetailView so the user doesn't have to open the
// full EditCarDetailView form to change a single field.
//
// Includes the insurance-card scanner (parseInsuranceCard) so populating a
// brand-new insurance record from a card photo is a one-tap flow.
struct EditInsuranceSheet: View {
    let car: Car
    let onSave: (Car) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var provider: String = ""
    @State private var policyNumber: String = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date()

    @State private var showingScanner = false
    @State private var isScanning = false
    @State private var scanResult: ScanPreview?
    @State private var scanError: DocumentScanService.ScanError?

    private let scanService = DocumentScanService()
    @EnvironmentObject private var scanAllowance: ScanAllowanceStore
    @State private var showingScanPaywall = false

    fileprivate struct ScanPreview: Identifiable {
        let id = UUID()
        let provider: String
        let policyNumber: String
        let expiryDate: Date?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Quick Fill")) {
                    scanRow
                }

                Section(header: Text("Insurance")) {
                    Picker("Provider", selection: $provider) {
                        Text("Select a provider").tag("")
                        ForEach(CarData.insuranceProviders, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Policy Number", text: $policyNumber)
                        .autocorrectionDisabled()

                    Toggle("Expiration", isOn: $hasExpiry.animation())
                        .onChange(of: hasExpiry) { _, isOn in
                            if isOn { NotificationManager.requestPermission() }
                        }
                    if hasExpiry {
                        DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Insurance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView(
                    onScan: { image in
                        showingScanner = false
                        Task { await processScan(image) }
                    },
                    onCancel: { showingScanner = false },
                    onError: { error in
                        showingScanner = false
                        scanError = .unknown(error.localizedDescription)
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $scanResult) { result in
                ScanConfirmationSheet(result: result, onUse: { apply(result) })
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
            .onAppear { populate() }
        }
    }

    // MARK: - Populate / Save

    private func populate() {
        provider = car.insuranceProvider
        policyNumber = car.insurancePolicyNumber
        if let date = car.insuranceExpiryDate {
            hasExpiry = true
            expiryDate = date
        }
    }

    private func save() {
        var updated = car
        updated.insuranceProvider = provider
        updated.insurancePolicyNumber = policyNumber.trimmingCharacters(in: .whitespaces)
        updated.insuranceExpiryDate = hasExpiry ? expiryDate : nil
        onSave(updated)
        dismiss()
    }

    // MARK: - Scan

    private var scanRow: some View {
        Button {
            if VNDocumentCameraViewController.isSupported {
                if scanAllowance.canStartScan() {
                    showingScanner = true
                } else {
                    showingScanPaywall = true
                }
            } else {
                scanError = .cameraUnsupported
            }
        } label: {
            HStack {
                Label("Scan Insurance Card", systemImage: "doc.text.viewfinder")
                Spacer()
                if isScanning { ProgressView() } else { ScanAllowanceCaption() }
            }
        }
        .disabled(isScanning)
        .scanCapPaywall(isPresented: $showingScanPaywall)
    }

    private func processScan(_ image: UIImage) async {
        isScanning = true
        scanError = nil
        defer { isScanning = false }

        do {
            let result = try await scanService.scanInsuranceCard(image: image)
            scanResult = ScanPreview(
                provider: result.provider,
                policyNumber: result.policyNumber,
                expiryDate: result.expiryDate
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

    // Merge-in policy: empty scan values don't overwrite existing typed values.
    private func apply(_ result: ScanPreview) {
        if !result.provider.isEmpty {
            let matched = CarData.insuranceProviders.first { $0.caseInsensitiveCompare(result.provider) == .orderedSame }
                ?? CarData.insuranceProviders.first(where: { result.provider.localizedCaseInsensitiveContains($0) })
            provider = matched ?? result.provider
        }
        if !result.policyNumber.isEmpty {
            policyNumber = result.policyNumber
        }
        if let expiry = result.expiryDate {
            expiryDate = expiry
            hasExpiry = true
        }
    }
}

// MARK: - Confirmation sheet

private struct ScanConfirmationSheet: View {
    let result: EditInsuranceSheet.ScanPreview
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
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Section("Extracted") {
                    LabeledContent("Provider", value: display(result.provider))
                    LabeledContent("Policy Number", value: display(result.policyNumber))
                    LabeledContent("Expires", value: displayDate(result.expiryDate))
                }
            }
            .navigationTitle("Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use These") { onUse(); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(!hasAny)
                }
            }
        }
    }

    private var hasAny: Bool {
        !result.provider.isEmpty || !result.policyNumber.isEmpty || result.expiryDate != nil
    }

    private func display(_ s: String) -> String { s.isEmpty ? "—" : s }
    private func displayDate(_ d: Date?) -> String { d?.formatted(date: .abbreviated, time: .omitted) ?? "—" }
}
