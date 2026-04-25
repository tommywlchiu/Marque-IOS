import SwiftUI
import PhotosUI
import Photos

struct EditCarDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var car: Car

    var onSave: (Car) -> Void

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

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var carImage: UIImage?
    @State private var photoFileName: String?
    @State private var photoOffsetY: Double = 0
    @State private var dragOffsetY: Double = 0
    @State private var showingPhotoPicker = false
    @State private var showingRemovePhotoAlert = false
    @State private var showingPhotoPermissionDenied = false

    var isFormValid: Bool {
        !make.trimmingCharacters(in: .whitespaces).isEmpty &&
        !model.trimmingCharacters(in: .whitespaces).isEmpty &&
        !year.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection

                Section(header: Text("Basic Information")) {
                    Picker("Make", selection: $make) {
                        Text("Select a make").tag("")
                        ForEach(CarData.makes, id: \.self) { brand in
                            Text(brand).tag(brand)
                        }
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
                        DatePicker(
                            "Expires",
                            selection: $registrationExpiryDate,
                            displayedComponents: .date
                        )
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
                        ForEach(CarData.insuranceProviders, id: \.self) { provider in
                            Text(provider).tag(provider)
                        }
                    }

                    TextField("Policy Number", text: $insurancePolicyNumber)
                        .autocorrectionDisabled()

                    Toggle("Insurance Expiry Date", isOn: $hasInsuranceExpiry.animation())
                        .onChange(of: hasInsuranceExpiry) { _, isOn in
                            if isOn { NotificationManager.requestPermission() }
                        }

                    if hasInsuranceExpiry {
                        DatePicker(
                            "Expires",
                            selection: $insuranceExpiryDate,
                            displayedComponents: .date
                        )
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCarPhoto()

                        var updatedCar = car
                        updatedCar.make = make
                        updatedCar.model = model.trimmingCharacters(in: .whitespaces)
                        updatedCar.year = year.trimmingCharacters(in: .whitespaces)
                        updatedCar.licensePlate = licensePlate.trimmingCharacters(in: .whitespaces)
                        updatedCar.vinNumber = vinNumber.trimmingCharacters(in: .whitespaces)
                        updatedCar.color = color.trimmingCharacters(in: .whitespaces)
                        updatedCar.mileage = mileage.trimmingCharacters(in: .whitespaces)
                        updatedCar.trim = trim.trimmingCharacters(in: .whitespaces)
                        updatedCar.bodyStyle = bodyStyle
                        updatedCar.driveType = driveType
                        updatedCar.engine = engine.trimmingCharacters(in: .whitespaces)
                        updatedCar.fuelType = fuelType
                        updatedCar.transmission = transmission
                        updatedCar.insuranceProvider = insuranceProvider
                        updatedCar.insurancePolicyNumber = insurancePolicyNumber.trimmingCharacters(in: .whitespaces)
                        updatedCar.insuranceExpiryDate = hasInsuranceExpiry ? insuranceExpiryDate : nil
                        updatedCar.registrationExpiryDate = hasRegistrationExpiry ? registrationExpiryDate : nil
                        updatedCar.notes = notes.trimmingCharacters(in: .whitespaces)
                        updatedCar.photoFileName = photoFileName
                        updatedCar.photoOffsetY = photoOffsetY
                        onSave(updatedCar)
                        dismiss()
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
            .confirmationDialog("Remove this photo?", isPresented: $showingRemovePhotoAlert, titleVisibility: .visible) {
                Button("Remove Photo", role: .destructive) {
                    carImage = nil
                    if let oldFile = photoFileName {
                        ImageManager.deleteImage(fileName: oldFile)
                    }
                    photoFileName = nil
                    selectedPhoto = nil
                    photoOffsetY = 0
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        carImage = image
                        photoOffsetY = 0
                    }
                }
            }
            .alert("Photo Access Denied", isPresented: $showingPhotoPermissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To add car photos, allow Marque to access your photo library in Settings.")
            }
            .onAppear {
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
                photoFileName = car.photoFileName
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
                    carImage = ImageManager.loadImage(fileName: fileName)
                }
            }
        }
    }

    private var photoSection: some View {
        Section(header: Text("Car Photo")) {
            VStack(spacing: 12) {
                if let carImage {
                    GeometryReader { geo in
                        let maxOff = maxPhotoOffset(image: carImage, width: geo.size.width, height: 180)
                        let clampedOffset = min(maxOff, max(-maxOff, photoOffsetY + dragOffsetY))

                        Image(uiImage: carImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: 180)
                            .offset(y: clampedOffset)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let proposed = photoOffsetY + value.translation.height
                                        dragOffsetY = min(maxOff, max(-maxOff, proposed)) - photoOffsetY
                                    }
                                    .onEnded { value in
                                        let proposed = photoOffsetY + value.translation.height
                                        photoOffsetY = min(maxOff, max(-maxOff, proposed))
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

                HStack(spacing: 16) {
                    Button {
                        requestPhotoAccess()
                    } label: {
                        Label(carImage == nil ? "Add Photo" : "Change Photo", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    if carImage != nil {
                        Button(role: .destructive) {
                            showingRemovePhotoAlert = true
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private func requestPhotoAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            showingPhotoPicker = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        showingPhotoPicker = true
                    } else {
                        showingPhotoPermissionDenied = true
                    }
                }
            }
        default:
            showingPhotoPermissionDenied = true
        }
    }

    private func maxPhotoOffset(image: UIImage, width: CGFloat, height: CGFloat) -> Double {
        let imageAspect = image.size.width / image.size.height
        let displayedHeight = width / imageAspect
        return max(0, (displayedHeight - height) / 2)
    }

    private func saveCarPhoto() {
        guard let image = carImage else {
            if photoFileName != nil && car.photoFileName != nil {
                photoFileName = nil
            }
            return
        }

        if photoFileName == nil || photoFileName != car.photoFileName {
            if let oldFile = car.photoFileName, oldFile != photoFileName {
                ImageManager.deleteImage(fileName: oldFile)
            }
            let newFileName = ImageManager.generateFileName()
            ImageManager.saveImage(image, fileName: newFileName)
            photoFileName = newFileName
        } else if let fileName = photoFileName {
            ImageManager.saveImage(image, fileName: fileName)
        }
    }
}

#Preview {
    EditCarDetailView(
        car: .constant(Car(
            make: "Toyota",
            model: "Camry",
            year: "2024"
        )),
        onSave: { _ in }
    )
}
