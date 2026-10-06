import SwiftUI

// Focused sheet for editing just a car's vehicle-details fields:
// color, mileage, trim, body style, drive type, engine, fuel type,
// transmission. Presented from the Vehicle Details section of
// CarDetailView. Mirrors the same shape/save pattern as
// EditRegistrationSheet and EditInsuranceSheet so all four section
// edit flows behave identically.
struct EditVehicleDetailsSheet: View {
    let car: Car
    let onSave: (Car) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var color: String = ""
    @State private var mileage: String = ""
    @State private var trim: String = ""
    @State private var bodyStyle: String = ""
    @State private var driveType: String = ""
    @State private var engine: String = ""
    @State private var fuelType: String = ""
    @State private var transmission: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details")) {
                    TextField("Color (e.g. Silver, Black)", text: $color)
                    TextField("Mileage (e.g. 25,000 mi)", text: $mileage)
                        .keyboardType(.numberPad)
                }

                Section(header: Text("Powertrain")) {
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
                    TextField("Engine (e.g. 2.5L 4-Cylinder)", text: $engine)
                        .autocorrectionDisabled()
                }

                Section(header: Text("Trim & Body")) {
                    TextField("Trim (e.g. EX-L, Sport, XLE)", text: $trim)
                        .autocorrectionDisabled()
                    Picker("Body Style", selection: $bodyStyle) {
                        Text("Select").tag("")
                        ForEach(CarData.bodyStyles, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Drive Type", selection: $driveType) {
                        Text("Select").tag("")
                        Text("FWD").tag("FWD")
                        Text("RWD").tag("RWD")
                        Text("AWD").tag("AWD")
                        Text("4WD").tag("4WD")
                    }
                }
            }
            .navigationTitle("Vehicle Details")
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
            .onAppear { populate() }
        }
    }

    private func populate() {
        color = car.color
        mileage = car.mileage
        trim = car.trim
        bodyStyle = car.bodyStyle
        driveType = car.driveType
        engine = car.engine
        fuelType = car.fuelType
        transmission = car.transmission
    }

    private func save() {
        var updated = car
        updated.color = color.trimmingCharacters(in: .whitespaces)
        updated.mileage = mileage.trimmingCharacters(in: .whitespaces)
        updated.trim = trim.trimmingCharacters(in: .whitespaces)
        updated.bodyStyle = bodyStyle
        updated.driveType = driveType
        updated.engine = engine.trimmingCharacters(in: .whitespaces)
        updated.fuelType = fuelType
        updated.transmission = transmission
        onSave(updated)
        dismiss()
    }
}
