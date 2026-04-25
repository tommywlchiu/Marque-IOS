import SwiftUI

private enum AddMode: String, CaseIterable {
    case vin = "VIN Decode"
    case manual = "Manual"
}

struct AddCarView: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss

    @State private var addMode: AddMode = .vin

    // VIN decode state
    @State private var vinInput = ""
    @State private var isDecoding = false
    @State private var decodeError: String?
    @State private var vinDecoded = false

    // Car fields (shared between modes, pre-filled by VIN decode)
    @State private var make = ""
    @State private var model = ""
    @State private var year = ""
    @State private var fuelType = ""
    @State private var transmission = ""

    var isFormValid: Bool {
        !make.trimmingCharacters(in: .whitespaces).isEmpty &&
        !model.trimmingCharacters(in: .whitespaces).isEmpty &&
        !year.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canAdd: Bool {
        isFormValid && (addMode == .manual || vinDecoded)
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
                } else if vinDecoded {
                    decodedResultSection
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
        Section(header: Text("Decode by VIN")) {
            HStack(spacing: 12) {
                TextField("17-character VIN", text: $vinInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: vinInput) { _, _ in
                        decodeError = nil
                        if vinDecoded { resetDecodedFields() }
                    }

                if isDecoding {
                    ProgressView()
                } else {
                    Button("Decode") {
                        Task { await decodeVIN() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vinInput.trimmingCharacters(in: .whitespaces).count != 17)
                }
            }

            if let error = decodeError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    private var decodedResultSection: some View {
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Vehicle decoded — review and edit if needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField("Make", text: $make)
                .autocorrectionDisabled()

            TextField("Model", text: $model)
                .autocorrectionDisabled()

            TextField("Year", text: $year)
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
        } header: {
            Text("Decoded Vehicle")
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

    private func decodeVIN() async {
        isDecoding = true
        decodeError = nil
        do {
            let result = try await VINDecodeService.decode(vin: vinInput)
            make = result.make
            model = result.model
            year = result.year
            fuelType = result.fuelType
            transmission = result.transmission
            vinDecoded = true
        } catch {
            decodeError = error.localizedDescription
        }
        isDecoding = false
    }

    private func resetDecodedFields() {
        vinDecoded = false
        make = ""
        model = ""
        year = ""
        fuelType = ""
        transmission = ""
    }

    private func resetFields() {
        vinInput = ""
        decodeError = nil
        resetDecodedFields()
    }
}

#Preview {
    AddCarView()
        .environmentObject(CarStore())
}
