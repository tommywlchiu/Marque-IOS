import SwiftUI

private enum AddMode: String, CaseIterable {
    case vin = "Search by VIN"
    case manual = "Manual"
}

struct AddCarView: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss

    @State private var addMode: AddMode = .vin

    // VIN search state
    @State private var vinInput = ""
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var vinSearched = false

    // Car fields (shared between modes, pre-filled by VIN search)
    @State private var make = ""
    @State private var model = ""
    @State private var year = ""
    @State private var trim = ""
    @State private var bodyStyle = ""
    @State private var driveType = ""
    @State private var engine = ""
    @State private var fuelType = ""
    @State private var transmission = ""

    var isFormValid: Bool {
        !make.trimmingCharacters(in: .whitespaces).isEmpty &&
        !model.trimmingCharacters(in: .whitespaces).isEmpty &&
        !year.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canAdd: Bool {
        isFormValid && (addMode == .manual || vinSearched)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Add Method", selection: $addMode.animation()) {
                        ForEach(AddMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .onChange(of: addMode) { _, _ in resetFields() }

                if addMode == .vin {
                    vinInputSection
                }

                if addMode == .manual {
                    manualSection
                } else if vinSearched {
                    searchResultSection
                }
            }
            .navigationTitle("Add a Car")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let car = Car(
                            make: make.trimmingCharacters(in: .whitespaces),
                            model: model.trimmingCharacters(in: .whitespaces),
                            year: year.trimmingCharacters(in: .whitespaces),
                            vinNumber: addMode == .vin ? vinInput.uppercased().trimmingCharacters(in: .whitespaces) : "",
                            trim: trim,
                            bodyStyle: bodyStyle,
                            driveType: driveType,
                            engine: engine,
                            fuelType: fuelType,
                            transmission: transmission
                        )
                        carStore.addCar(car)
                        dismiss()
                    }
                    .disabled(!canAdd)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var vinInputSection: some View {
        Section(header: Text("Search by VIN")) {
            HStack(spacing: 12) {
                TextField("17-character VIN", text: $vinInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: vinInput) { _, _ in
                        searchError = nil
                        if vinSearched { resetSearchedFields() }
                    }

                if isSearching {
                    ProgressView()
                } else {
                    Button("Search") {
                        Task { await searchVIN() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vinInput.trimmingCharacters(in: .whitespaces).count != 17)
                }
            }

            if let error = searchError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    private var searchResultSection: some View {
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Vehicle found — review and edit if needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField("Make", text: $make)
                .autocorrectionDisabled()

            TextField("Model", text: $model)
                .autocorrectionDisabled()

            TextField("Year", text: $year)
                .keyboardType(.numberPad)

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
        } header: {
            Text("Search Results")
        } footer: {
            Text("You can add color, mileage, insurance, and other details after adding the car.")
        }
    }

    private var manualSection: some View {
        Group {
            Section(header: Text("Car Information")) {
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

            Section {
                Text("You can add license plate, VIN, and other details after adding the car.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func searchVIN() async {
        isSearching = true
        searchError = nil
        do {
            let result = try await VINDecodeService.decode(vin: vinInput)
            make = result.make
            model = result.model
            year = result.year
            trim = result.trim
            bodyStyle = result.bodyStyle
            driveType = result.driveType
            engine = result.engine
            fuelType = result.fuelType
            transmission = result.transmission
            vinSearched = true
        } catch {
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    private func resetSearchedFields() {
        vinSearched = false
        make = ""
        model = ""
        year = ""
        trim = ""
        bodyStyle = ""
        driveType = ""
        engine = ""
        fuelType = ""
        transmission = ""
    }

    private func resetFields() {
        vinInput = ""
        searchError = nil
        resetSearchedFields()
    }
}

#Preview {
    AddCarView()
        .environmentObject(CarStore())
}
