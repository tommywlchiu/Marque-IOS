import SwiftUI
import PhotosUI
import Photos

// Tracks what the user has done to the photo during this edit session.
// File I/O only happens when the user taps Save.
private enum PhotoEditState {
    case unchanged          // no change — persist car.photoFileName as-is
    case selected(UIImage)  // new image picked — save to disk on commit
    case removed            // user confirmed removal — delete from disk on commit
}

struct EditCarDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var car: Car

    var onSave: (Car) -> Void

    // MARK: - Form fields

    @State private var make: String = ""
    @State private var model: String = ""
    @State private var year: String = ""
    @State private var licensePlate: String = ""
    @State private var vinNumber: String = ""
    @State private var color: String = ""
    @State private var mileage: String = ""
    @State private var trim: String = ""
    @State private var bodyStyle: String = ""
    @State private var driveType: String = ""
    @State private var engine: String = ""
    @State private var fuelType: String = ""
    @State private var transmission: String = ""
    @State private var insuranceProvider: String = ""
    @State private var insurancePolicyNumber: String = ""
    @State private var notes: String = ""

    @State private var hasInsuranceExpiry = false
    @State private var insuranceExpiryDate = Date()
    @State private var hasRegistrationExpiry = false
    @State private var registrationExpiryDate = Date()

    // MARK: - Photo state

    @State private var photoState: PhotoEditState = .unchanged
    @State private var loadedImage: UIImage?        // image read from disk on appear
    @State private var selectedItem: PhotosPickerItem?
    @State private var photoOffsetY: Double = 0
    @State private var dragOffsetY: Double = 0
    @State private var showingPicker = false
    @State private var showingRemoveConfirmation = false
    @State private var showingPermissionDenied = false

    // MARK: - Derived

    private var displayImage: UIImage? {
        switch photoState {
        case .unchanged:         return loadedImage
        case .selected(let img): return img
        case .removed:           return nil
        }
    }

    var isFormValid: Bool {
        !make.trimmingCharacters(in: .whitespaces).isEmpty &&
        !model.trimmingCharacters(in: .whitespaces).isEmpty &&
        !year.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                photoSection

                Section(header: Text("Basic Information")) {
                    Picker("Make", selection: $make) {
                        Text("Select a make").tag("")
                        ForEach(CarData.makes, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Model (e.g. Camry, 3 Series)", text: $model)
                        .autocorrectionDisabled()
                    TextField("Year (e.g. 2024)", text: $year)
                        .keyboardType(.numberPad)
                }

                Section(header: Text("Registration & Identification")) {
                    TextField("License Plate Number", text: $licensePlate)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    TextField("VIN Number", text: $vinNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)

                    Toggle("Registration Expiry Date", isOn: $hasRegistrationExpiry.animation())
                        .onChange(of: hasRegistrationExpiry) { _, isOn in
                            if isOn { NotificationManager.requestPermission() }
                        }
                    if hasRegistrationExpiry {
                        DatePicker("Expires", selection: $registrationExpiryDate, displayedComponents: .date)
                    }
                }

                Section(header: Text("Vehicle Details")) {
                    TextField("Color (e.g. Silver, Black)", text: $color)
                    TextField("Mileage (e.g. 25,000 mi)", text: $mileage)
                        .keyboardType(.numberPad)

                    Picker("Fuel Type", selection: $fuelType) {
                        Text("Select").tag("")
                        Text("Gasoline").tag("Gasoline")
                        Text("Diesel").tag("Diesel")
                        Text("Electric").tag("Electric")
                        Text("Hybrid").tag("Hybrid")
                        Text("Plug-in Hybrid").tag("Plug-in Hybrid")
                        Text("Flex Fuel").tag("Flex Fuel")
                    }

                    Picker("Transmission", selection: $transmission) {
                        Text("Select").tag("")
                        Text("Automatic").tag("Automatic")
                        Text("Manual").tag("Manual")
                        Text("CVT").tag("CVT")
                        Text("Dual-Clutch").tag("Dual-Clutch")
                    }

                    TextField("Trim (e.g. EX-L, Sport, XLE)", text: $trim)
                        .autocorrectionDisabled()

                    Picker("Body Style", selection: $bodyStyle) {
                        Text("Select").tag("")
                        Text("Sedan").tag("Sedan")
                        Text("Coupe").tag("Coupe")
                        Text("Hatchback").tag("Hatchback")
                        Text("SUV").tag("SUV")
                        Text("Crossover").tag("Crossover")
                        Text("Pickup").tag("Pickup")
                        Text("Van").tag("Van")
                        Text("Minivan").tag("Minivan")
                        Text("Wagon").tag("Wagon")
                        Text("Convertible").tag("Convertible")
                    }

                    Picker("Drive Type", selection: $driveType) {
                        Text("Select").tag("")
                        Text("FWD").tag("FWD")
                        Text("RWD").tag("RWD")
                        Text("AWD").tag("AWD")
                        Text("4WD").tag("4WD")
                    }

                    TextField("Engine (e.g. 2.5L 4-Cylinder)", text: $engine)
                        .autocorrectionDisabled()
                }

                Section(header: Text("Insurance Information")) {
                    Picker("Insurance Provider", selection: $insuranceProvider) {
                        Text("Select a provider").tag("")
                        ForEach(CarData.insuranceProviders, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Policy Number", text: $insurancePolicyNumber)
                        .autocorrectionDisabled()

                    Toggle("Insurance Expiry Date", isOn: $hasInsuranceExpiry.animation())
                        .onChange(of: hasInsuranceExpiry) { _, isOn in
                            if isOn { NotificationManager.requestPermission() }
                        }
                    if hasInsuranceExpiry {
                        DatePicker("Expires", selection: $insuranceExpiryDate, displayedComponents: .date)
                    }
                }

                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Car Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCar() }
                        .disabled(!isFormValid)
                        .fontWeight(.semibold)
                }
            }
            // Permission-denied alert lives here alone — no other presentation modifiers
            // on NavigationStack to avoid SwiftUI presentation conflicts.
            .alert("Photo Access Required", isPresented: $showingPermissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To add a car photo, allow Marque to access your photo library in Settings > Privacy > Photos.")
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    guard let newItem,
                          let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    photoState = .selected(image)
                    photoOffsetY = 0
                }
            }
            .onAppear {
                populateFields()
            }
        }
    }

    // MARK: - Photo section

    private var photoSection: some View {
        Section(header: Text("Car Photo")) {
            VStack(spacing: 12) {
                if let image = displayImage {
                    photoPreview(image: image)
                }

                HStack(spacing: 16) {
                    // Add / Change — .photosPicker is scoped to this button only.
                    Button {
                        requestPhotoPermission()
                    } label: {
                        Label(
                            displayImage == nil ? "Add Photo" : "Change Photo",
                            systemImage: "photo.on.rectangle.angled"
                        )
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .photosPicker(
                        isPresented: $showingPicker,
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    )

                    // Remove — .confirmationDialog is scoped to this button only,
                    // keeping it isolated from the picker above.
                    if displayImage != nil {
                        Button(role: .destructive) {
                            showingRemoveConfirmation = true
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.subheadline)
                        }
                        .confirmationDialog(
                            "Remove Photo",
                            isPresented: $showingRemoveConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Remove Photo", role: .destructive) {
                                if let old = car.photoFileName {
                                    ImageManager.deleteImage(fileName: old)
                                }
                                photoState = .removed
                                photoOffsetY = 0
                            }
                        } message: {
                            Text("This will permanently remove the photo.")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func photoPreview(image: UIImage) -> some View {
        GeometryReader { geo in
            let maxOffset = clampedMaxOffset(image: image, width: geo.size.width, height: 180)
            let offset = min(maxOffset, max(-maxOffset, photoOffsetY + dragOffsetY))

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: 180)
                .offset(y: offset)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let proposed = photoOffsetY + value.translation.height
                            dragOffsetY = min(maxOffset, max(-maxOffset, proposed)) - photoOffsetY
                        }
                        .onEnded { value in
                            let proposed = photoOffsetY + value.translation.height
                            photoOffsetY = min(maxOffset, max(-maxOffset, proposed))
                            dragOffsetY = 0
                        }
                )
        }
        .frame(height: 180)

        HStack(spacing: 4) {
            Image(systemName: "arrow.up.and.down")
                .font(.caption2)
            Text("Drag to reposition")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Permission

    private func requestPhotoPermission() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            showingPicker = true

        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized, .limited:
                        showingPicker = true
                    default:
                        showingPermissionDenied = true
                    }
                }
            }

        default:
            showingPermissionDenied = true
        }
    }

    // MARK: - Helpers

    private func clampedMaxOffset(image: UIImage, width: CGFloat, height: CGFloat) -> Double {
        let displayedHeight = width / (image.size.width / image.size.height)
        return max(0, (displayedHeight - height) / 2)
    }

    // MARK: - Save

    /// Persists any pending photo change and returns the new filename (or nil if removed).
    private func commitPhotoChanges() -> String? {
        switch photoState {
        case .unchanged:
            return car.photoFileName

        case .removed:
            // File was already deleted when the user confirmed the removal dialog.
            return nil

        case .selected(let image):
            if let old = car.photoFileName {
                ImageManager.deleteImage(fileName: old)
            }
            let fileName = ImageManager.generateFileName()
            ImageManager.saveImage(image, fileName: fileName)
            return fileName
        }
    }

    private func saveCar() {
        let newPhotoFileName = commitPhotoChanges()

        var updated = car
        updated.make = make
        updated.model = model.trimmingCharacters(in: .whitespaces)
        updated.year = year.trimmingCharacters(in: .whitespaces)
        updated.licensePlate = licensePlate.trimmingCharacters(in: .whitespaces)
        updated.vinNumber = vinNumber.trimmingCharacters(in: .whitespaces)
        updated.color = color.trimmingCharacters(in: .whitespaces)
        updated.mileage = mileage.trimmingCharacters(in: .whitespaces)
        updated.trim = trim.trimmingCharacters(in: .whitespaces)
        updated.bodyStyle = bodyStyle
        updated.driveType = driveType
        updated.engine = engine.trimmingCharacters(in: .whitespaces)
        updated.fuelType = fuelType
        updated.transmission = transmission
        updated.insuranceProvider = insuranceProvider
        updated.insurancePolicyNumber = insurancePolicyNumber.trimmingCharacters(in: .whitespaces)
        updated.insuranceExpiryDate = hasInsuranceExpiry ? insuranceExpiryDate : nil
        updated.registrationExpiryDate = hasRegistrationExpiry ? registrationExpiryDate : nil
        updated.notes = notes.trimmingCharacters(in: .whitespaces)
        updated.photoFileName = newPhotoFileName
        updated.photoOffsetY = photoOffsetY

        onSave(updated)
        dismiss()
    }

    private func populateFields() {
        make = car.make
        model = car.model
        year = car.year
        licensePlate = car.licensePlate
        vinNumber = car.vinNumber
        color = car.color
        mileage = car.mileage
        trim = car.trim
        bodyStyle = car.bodyStyle
        driveType = car.driveType
        engine = car.engine
        fuelType = car.fuelType
        transmission = car.transmission
        insuranceProvider = car.insuranceProvider
        insurancePolicyNumber = car.insurancePolicyNumber
        notes = car.notes
        photoOffsetY = car.photoOffsetY

        if let date = car.insuranceExpiryDate {
            hasInsuranceExpiry = true
            insuranceExpiryDate = date
        }
        if let date = car.registrationExpiryDate {
            hasRegistrationExpiry = true
            registrationExpiryDate = date
        }
        if let fileName = car.photoFileName {
            loadedImage = ImageManager.loadImage(fileName: fileName)
        }
    }
}

#Preview {
    EditCarDetailView(
        car: .constant(Car(make: "Toyota", model: "Camry", year: "2024")),
        onSave: { _ in }
    )
}
