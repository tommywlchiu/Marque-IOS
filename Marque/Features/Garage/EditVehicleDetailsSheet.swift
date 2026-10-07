import SwiftUI

// Focused sheet for editing just a car's vehicle-details fields:
// color, mileage, trim, body style, drive type, engine, fuel type,
// range (electric/hybrid/diesel only), tank size (diesel/hybrid),
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
    @State private var fullRange: String = ""
    @State private var tankGallons: String = ""
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
                    if Car.tracksTankSize(fuelType: fuelType) {
                        LabeledContent("Tank Size") {
                            TextField("e.g. 18.5 gal", text: $tankGallons)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let kind = Car.RangeKind(fuelType: fuelType) {
                        LabeledContent(kind.label) {
                            TextField(rangePlaceholder(kind), text: $fullRange)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
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
        fullRange = car.fullRange.map(String.init) ?? ""
        tankGallons = car.tankGallons.map { $0.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)) } ?? ""
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
        // Kept even if the fuel type no longer shows a range, so switching
        // the picker back and forth doesn't lose it.
        let typedRange = NumberParsing.mileage(from: fullRange)
        if typedRange != car.fullRange {
            // The owner changed it (or cleared it, which lets the EPA
            // estimate fill it back in): their number, not an estimate.
            updated.fullRange = typedRange
            updated.fullRangeIsEstimate = false
        }
        updated.tankGallons = Self.gallons(from: tankGallons)
        updated.transmission = transmission
        onSave(updated)
        dismiss()
    }

    /// Blank range: says the EPA estimate fills it in (for a hybrid or
    /// diesel, once there's a tank size).
    private func rangePlaceholder(_ kind: Car.RangeKind) -> String {
        if Car.tracksTankSize(fuelType: fuelType) && Self.gallons(from: tankGallons) == nil {
            return "Add tank size for EPA est."
        }
        return "EPA estimate"
    }

    /// "18.5", "18,5" or "18.5 gal" -> 18.5; nil if blank, zero or absurd.
    private static func gallons(from text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(cleaned), value > 0, value < 200 else { return nil }
        return value
    }
}
