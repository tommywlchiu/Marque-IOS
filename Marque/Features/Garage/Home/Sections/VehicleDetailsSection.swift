import SwiftUI

/// The spec fields shown in "Vehicle Details". Built from either the owner's
/// `Car` or a `PublicCar` (whose fields are already filtered by the owner's
/// sharing settings), so both car-page modes render through one section.
struct VehicleSpecs {
    var color = ""
    var mileage = ""
    var fuelType = ""
    var rangeLabel = ""  // "Range (full charge)" / "Range (full tank)"
    var range = ""       // owner's car only; range isn't public
    var tankSize = ""    // diesel, owner's car only
    var transmission = ""
    var trim = ""
    var bodyStyle = ""
    var driveType = ""
    var engine = ""

    init(car: Car) {
        color = car.color
        mileage = car.mileage
        fuelType = car.fuelType
        if let kind = car.rangeKind, let text = car.rangeText {
            rangeLabel = kind.label
            range = car.fullRangeIsEstimate ? "\(text) · EPA est." : text
        }
        tankSize = car.tankSizeText ?? ""
        transmission = car.transmission
        trim = car.trim
        bodyStyle = car.bodyStyle
        driveType = car.driveType
        engine = car.engine
    }

    init(publicCar: PublicCar) {
        color = publicCar.color
        mileage = publicCar.mileage
        fuelType = publicCar.fuelType
        transmission = publicCar.transmission
        trim = publicCar.trim
        bodyStyle = publicCar.bodyStyle
        driveType = publicCar.driveType
        engine = publicCar.engine
    }

    var isEmpty: Bool {
        [color, mileage, fuelType, range, tankSize, transmission, trim, bodyStyle, driveType, engine].allSatisfy(\.isEmpty)
    }
}

/// "Vehicle Details". With `onEdit` (owner) it shows an edit pencil and an
/// empty-state CTA; without it (someone else's public car) it's read-only and
/// the caller hides it when `specs.isEmpty`.
struct VehicleDetailsSection: View {
    let specs: VehicleSpecs
    var onEdit: (() -> Void)? = nil

    var body: some View {
        Section(header: header) {
            if specs.isEmpty, let onEdit {
                EmptySectionRow(title: "Add Vehicle Details", action: onEdit)
            } else {
                if !specs.color.isEmpty        { DetailRow(label: "Color", value: specs.color) }
                if !specs.mileage.isEmpty      { DetailRow(label: "Mileage", value: specs.mileage) }
                if !specs.fuelType.isEmpty     { DetailRow(label: "Fuel Type", value: specs.fuelType) }
                if !specs.range.isEmpty        { DetailRow(label: specs.rangeLabel, value: specs.range) }
                if !specs.tankSize.isEmpty     { DetailRow(label: "Tank Size", value: specs.tankSize) }
                if !specs.transmission.isEmpty { DetailRow(label: "Transmission", value: specs.transmission) }
                if !specs.trim.isEmpty         { DetailRow(label: "Trim", value: specs.trim) }
                if !specs.bodyStyle.isEmpty    { DetailRow(label: "Body Style", value: specs.bodyStyle) }
                if !specs.driveType.isEmpty    { DetailRow(label: "Drive Type", value: specs.driveType) }
                if !specs.engine.isEmpty       { DetailRow(label: "Engine", value: specs.engine) }
            }
        }
        .garageRowBackground()
    }

    @ViewBuilder
    private var header: some View {
        if let onEdit {
            EditableSectionHeader(title: "Vehicle Details", hasData: !specs.isEmpty, onEdit: onEdit)
        } else {
            Text("Vehicle Details")
        }
    }
}

/// Make / Model / Year. Shared by both car-page modes.
struct BasicInfoSection: View {
    let make: String
    let model: String
    let year: String

    var body: some View {
        Section(header: Text("Basic Information")) {
            DetailRow(label: "Make", value: make)
            DetailRow(label: "Model", value: model)
            DetailRow(label: "Year", value: year)
        }
        .garageRowBackground()
    }
}
