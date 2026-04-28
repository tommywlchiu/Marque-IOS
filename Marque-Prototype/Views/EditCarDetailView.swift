import SwiftUI
import PhotosUI
import Photos

// One photo in the editor's working list. Either it's already on disk
// (`.existing`) or the user just picked it and we haven't saved it yet
// (`.pending`). All disk I/O is deferred to commit time.
private enum PhotoSlot: Identifiable, Equatable {
    case existing(String)
    case pending(UIImage, UUID)

    var id: String {
        switch self {
        case .existing(let name): return name
        case .pending(_, let id): return id.uuidString
        }
    }

    static func == (lhs: PhotoSlot, rhs: PhotoSlot) -> Bool {
        lhs.id == rhs.id
    }
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

    @State private var photoSlots: [PhotoSlot] = []
    @State private var fileNamesToDelete: Set<String> = []   // existing files removed by the user
    @State private var primaryImage: UIImage?                 // resolved image for the first slot, used for reposition preview
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var photoOffsetY: Double = 0
    @State private var dragOffsetY: Double = 0
    @State private var showingPicker = false
    @State private var slotPendingRemoval: PhotoSlot?
    @State private var showingPermissionDenied = false

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
            .alert("Photo Access Required", isPresented: $showingPermissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To add car photos, allow Marque to access your photo library in Settings > Privacy > Photos.")
            }
            .photosPicker(
                isPresented: $showingPicker,
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPickedPhotos(items) }
            }
            .confirmationDialog(
                "Remove Photo",
                isPresented: Binding(
                    get: { slotPendingRemoval != nil },
                    set: { if !$0 { slotPendingRemoval = nil } }
                ),
                titleVisibility: .visible,
                presenting: slotPendingRemoval
            ) { slot in
                Button("Remove Photo", role: .destructive) { remove(slot: slot) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This will permanently remove the photo when you save.")
            }
            .onAppear { populateFields() }
        }
    }

    // MARK: - Photo section

    private var photoSection: some View {
        Section(header: Text("Car Photos")) {
            VStack(spacing: 12) {
                if let primaryImage {
                    photoPreview(image: primaryImage)
                }

                if photoSlots.count > 1 {
                    thumbnailStrip
                }

                Button {
                    requestPhotoPermission()
                } label: {
                    Label(
                        photoSlots.isEmpty ? "Add Photo" : "Add More Photos",
                        systemImage: "photo.on.rectangle.angled"
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
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
            Text("Drag to reposition cover photo")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(photoSlots.enumerated()), id: \.element.id) { index, slot in
                    thumbnailView(for: slot, index: index)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func thumbnailView(for slot: PhotoSlot, index: Int) -> some View {
        let image = thumbnailImage(for: slot)
        let isPrimary = index == 0

        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray5))
                        .frame(width: 64, height: 64)
                        .overlay(ProgressView().scaleEffect(0.7))
                }

                if isPrimary {
                    Text("Cover")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isPrimary ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contextMenu {
                if !isPrimary {
                    Button {
                        makePrimary(slot: slot)
                    } label: {
                        Label("Set as Cover", systemImage: "star")
                    }
                }
                Button(role: .destructive) {
                    slotPendingRemoval = slot
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }

            Button {
                slotPendingRemoval = slot
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .offset(x: 6, y: -6)
        }
    }

    // MARK: - Slot operations

    private func add(image: UIImage) {
        photoSlots.append(.pending(image, UUID()))
        if photoSlots.count == 1 {
            primaryImage = image
            photoOffsetY = 0
        }
    }

    private func remove(slot: PhotoSlot) {
        guard let index = photoSlots.firstIndex(of: slot) else { return }
        if case .existing(let fileName) = slot {
            fileNamesToDelete.insert(fileName)
        }
        let wasPrimary = index == 0
        photoSlots.remove(at: index)
        if wasPrimary {
            photoOffsetY = 0
            refreshPrimaryImage()
        }
    }

    private func makePrimary(slot: PhotoSlot) {
        guard let index = photoSlots.firstIndex(of: slot), index != 0 else { return }
        photoSlots.remove(at: index)
        photoSlots.insert(slot, at: 0)
        photoOffsetY = 0
        refreshPrimaryImage()
    }

    private func refreshPrimaryImage() {
        guard let first = photoSlots.first else {
            primaryImage = nil
            return
        }
        primaryImage = thumbnailImage(for: first)
    }

    private func thumbnailImage(for slot: PhotoSlot) -> UIImage? {
        switch slot {
        case .existing(let fileName): return ImageManager.loadImage(fileName: fileName)
        case .pending(let image, _):  return image
        }
    }

    // MARK: - Picker

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        var loadedImages: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loadedImages.append(image)
            }
        }
        await MainActor.run {
            for image in loadedImages { add(image: image) }
            selectedItems = []
        }
    }

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

    // Persists pending images to disk, deletes any removed files, and returns
    // the final ordered list of filenames for `car.photoFileNames`.
    private func commitPhotoChanges() -> [String] {
        var result: [String] = []
        for slot in photoSlots {
            switch slot {
            case .existing(let name):
                result.append(name)
            case .pending(let image, _):
                let name = ImageManager.generateFileName()
                ImageManager.saveImage(image, fileName: name)
                result.append(name)
            }
        }
        for name in fileNamesToDelete {
            ImageManager.deleteImage(fileName: name)
        }
        return result
    }

    private func saveCar() {
        let newFileNames = commitPhotoChanges()

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
        updated.photoFileNames = newFileNames
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

        photoSlots = car.photoFileNames.map { .existing($0) }
        if let firstName = car.photoFileNames.first {
            primaryImage = ImageManager.loadImage(fileName: firstName)
        }
    }
}

#Preview {
    EditCarDetailView(
        car: .constant(Car(make: "Toyota", model: "Camry", year: "2024")),
        onSave: { _ in }
    )
}
