import SwiftUI
import PhotosUI
import VisionKit

struct EditProfileView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var location = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var licenseNumber = ""
    @State private var licenseState = ""
    @State private var licenseExpiryDate: Date = Date()
    @State private var hasLicenseExpiryDate = false
    @State private var showLicenseNumber = false

    @State private var showingDocumentScanner = false
    @State private var isScanningLicense = false
    @State private var scanResult: ScanResultPreview?
    @State private var scanError: DocumentScanService.ScanError?

    private let scanService = DocumentScanService()

    // Wraps the extracted fields so we can drive a .sheet(item:) presentation.
    // fileprivate so LicenseScanConfirmationSheet (declared below) can see it.
    fileprivate struct ScanResultPreview: Identifiable {
        let id = UUID()
        let number: String
        let state: String
        let expiryDate: Date?
    }

    private var hasChanges: Bool {
        let user = authService.currentUser ?? .preview
        let currentExpiry = user.driverLicenseExpiryDate
        let newExpiry: Date? = hasLicenseExpiryDate ? licenseExpiryDate : nil
        return avatarImage != nil ||
               displayName != user.displayName ||
               username != user.username ||
               bio != user.bio ||
               location != user.location ||
               licenseNumber != user.driverLicenseNumber ||
               licenseState != user.driverLicenseState ||
               newExpiry != currentExpiry
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
                avatarSection
                infoSection
                bioSection
                driverLicenseSection
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Button("Save") { Task { await save() } }
                                .fontWeight(.semibold)
                                .disabled(!hasChanges)
                        }
                    }
                }
            }
            .onAppear { populateFields() }
            .onChange(of: selectedItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        avatarImage = image
                    }
                }
            }
            .fullScreenCover(isPresented: $showingDocumentScanner) {
                DocumentScannerView(
                    onScan: { image in
                        showingDocumentScanner = false
                        Task { await processScannedImage(image) }
                    },
                    onCancel: { showingDocumentScanner = false },
                    onError: { error in
                        showingDocumentScanner = false
                        scanError = .unknown(error.localizedDescription)
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $scanResult) { result in
                LicenseScanConfirmationSheet(
                    result: result,
                    onUse: { applyScanResult(result) }
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

    // MARK: - Sections

    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    avatarPreview
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Text("Change Photo")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let image = avatarImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
        } else if let user = authService.currentUser {
            UserAvatar(user: user, size: 80)
        }
    }

    private var infoSection: some View {
        Section(header: Text("Your Info")) {
            LabeledContent("Name") {
                TextField("Full Name", text: $displayName)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }

            LabeledContent("Username") {
                HStack(spacing: 4) {
                    Text("@").foregroundColor(.secondary)
                    TextField("username", text: $username)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            LabeledContent("Location") {
                TextField("City, State", text: $location)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
        }
    }

    private var bioSection: some View {
        Section(header: Text("Bio"), footer: Text("\(bio.count)/160 characters")) {
            TextEditor(text: $bio)
                .frame(minHeight: 80)
                .onChange(of: bio) { _, new in
                    if new.count > 160 { bio = String(new.prefix(160)) }
                }
        }
    }

    private var driverLicenseSection: some View {
        Section(
            header: Text("Driver License"),
            footer: Text("Stored only on this device for your reference. Never visible to other users.")
        ) {
            scanLicenseRow

            LabeledContent("Number") {
                HStack(spacing: 8) {
                    Group {
                        if showLicenseNumber {
                            TextField("D1234567", text: $licenseNumber)
                        } else {
                            SecureField("D1234567", text: $licenseNumber)
                        }
                    }
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)

                    Button {
                        showLicenseNumber.toggle()
                    } label: {
                        Image(systemName: showLicenseNumber ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showLicenseNumber ? "Hide license number" : "Show license number")
                }
            }

            LabeledContent("State") {
                TextField("CA", text: $licenseState)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: licenseState) { _, new in
                        // Cap at two characters and uppercase — state abbreviation.
                        if new.count > 2 { licenseState = String(new.prefix(2)).uppercased() }
                        else if new != new.uppercased() { licenseState = new.uppercased() }
                    }
            }

            Toggle("Track Expiration", isOn: $hasLicenseExpiryDate.animation())
            if hasLicenseExpiryDate {
                DatePicker(
                    "Expires",
                    selection: $licenseExpiryDate,
                    displayedComponents: .date
                )
            }
        }
    }

    private var scanLicenseRow: some View {
        Button {
            if VNDocumentCameraViewController.isSupported {
                showingDocumentScanner = true
            } else {
                scanError = .cameraUnsupported
            }
        } label: {
            HStack {
                Label("Scan License", systemImage: "doc.text.viewfinder")
                Spacer()
                if isScanningLicense {
                    ProgressView()
                }
            }
        }
        .disabled(isScanningLicense)
    }

    // MARK: - License scan

    private func processScannedImage(_ image: UIImage) async {
        isScanningLicense = true
        scanError = nil
        defer { isScanningLicense = false }

        do {
            let result = try await scanService.scanDriverLicense(image: image)
            scanResult = ScanResultPreview(
                number: result.number,
                state: result.state,
                expiryDate: result.expiryDate
            )
        } catch let error as DocumentScanService.ScanError {
            scanError = error
        } catch {
            scanError = .unknown(error.localizedDescription)
        }
    }

    private func applyScanResult(_ result: ScanResultPreview) {
        if !result.number.isEmpty { licenseNumber = result.number }
        if !result.state.isEmpty { licenseState = result.state }
        if let expiry = result.expiryDate {
            licenseExpiryDate = expiry
            hasLicenseExpiryDate = true
        }
    }

    // MARK: - Actions

    private func populateFields() {
        let user = authService.currentUser ?? .preview
        displayName = user.displayName
        username = user.username
        bio = user.bio
        location = user.location
        licenseNumber = user.driverLicenseNumber
        licenseState = user.driverLicenseState
        if let expiry = user.driverLicenseExpiryDate {
            licenseExpiryDate = expiry
            hasLicenseExpiryDate = true
        } else {
            // Default to one year from now to give a reasonable starting point
            // when the user toggles the date on for the first time.
            licenseExpiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
            hasLicenseExpiryDate = false
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let currentUsername = authService.currentUser?.username ?? ""

        if trimmedUsername != currentUsername {
            do {
                try await authService.changeUsername(to: trimmedUsername)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        var avatarFileName: String? = nil
        if let image = avatarImage, let uid = authService.currentUser?.id {
            let fileName = "avatar-\(uid).jpg"
            ImageManager.saveImage(image, fileName: fileName)
            avatarFileName = fileName
        }
        authService.updateProfile(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            username: authService.currentUser?.username ?? trimmedUsername,
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location.trimmingCharacters(in: .whitespaces),
            avatarFileName: avatarFileName
        )
        authService.updateDriverLicense(
            number: licenseNumber,
            state: licenseState,
            expiryDate: hasLicenseExpiryDate ? licenseExpiryDate : nil
        )
        dismiss()
    }
}

// MARK: - License scan confirmation sheet

private struct LicenseScanConfirmationSheet: View {
    let result: EditProfileView.ScanResultPreview
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
                    LabeledContent("Number", value: displayValue(result.number))
                    LabeledContent("State", value: displayValue(result.state))
                    LabeledContent("Expires", value: displayExpiry(result.expiryDate))
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
        !result.number.isEmpty || !result.state.isEmpty || result.expiryDate != nil
    }

    private func displayValue(_ s: String) -> String {
        s.isEmpty ? "—" : s
    }

    private func displayExpiry(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
