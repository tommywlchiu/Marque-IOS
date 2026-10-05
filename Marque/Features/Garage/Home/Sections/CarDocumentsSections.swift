import SwiftUI

// Registration and insurance sections for the owner's car (private fields —
// never used for someone else's public car). Extracted from CarDetailView;
// used by it and by the Garage's Documents screen.

struct RegistrationSection: View {
    let car: Car
    let onEdit: () -> Void

    private var hasData: Bool {
        !car.licensePlate.isEmpty || !car.vinNumber.isEmpty || car.registrationExpiryDate != nil
    }

    var body: some View {
        Section(header: EditableSectionHeader(title: "Registration & Identification", hasData: hasData, onEdit: onEdit)) {
            if hasData {
                if !car.licensePlate.isEmpty { DetailRow(label: "License Plate", value: car.licensePlate) }
                if !car.vinNumber.isEmpty { DetailRow(label: "VIN Number", value: car.vinNumber) }
                if let regDate = car.registrationExpiryDate {
                    ExpiryRow(
                        label: "Registration Expires",
                        date: regDate,
                        isExpired: car.isRegistrationExpired,
                        isExpiringSoon: car.isRegistrationExpiringSoon
                    )
                }
            } else {
                EmptySectionRow(title: "Add License Plate & VIN", action: onEdit)
            }
        }
        .garageRowBackground()
    }
}

struct InsuranceSection: View {
    let car: Car
    let onEdit: () -> Void

    private var hasData: Bool {
        !car.insuranceProvider.isEmpty || !car.insurancePolicyNumber.isEmpty || car.insuranceExpiryDate != nil
    }

    var body: some View {
        Section(header: EditableSectionHeader(title: "Insurance", hasData: hasData, onEdit: onEdit)) {
            if hasData {
                if !car.insuranceProvider.isEmpty { DetailRow(label: "Provider", value: car.insuranceProvider) }
                if !car.insurancePolicyNumber.isEmpty { DetailRow(label: "Policy Number", value: car.insurancePolicyNumber) }
                if let insDate = car.insuranceExpiryDate {
                    ExpiryRow(
                        label: "Insurance Expires",
                        date: insDate,
                        isExpired: car.isInsuranceExpired,
                        isExpiringSoon: car.isInsuranceExpiringSoon
                    )
                }
            } else {
                EmptySectionRow(title: "Add Insurance Info", action: onEdit)
            }
        }
        .garageRowBackground()
    }
}

// MARK: - Focused-edit presenter cluster
//
// Wraps the per-section focused sheets (Registration, Vehicle Details,
// Insurance, Add Reminder) into a single modifier so a caller's trailing
// modifier chain stays cheap for the SwiftUI type checker. Same technique
// used in EditCarDetailView after the "unable to type-check in reasonable
// time" error surfaced there.
struct FocusedEditPresenters: ViewModifier {
    let liveCar: Car?
    @Binding var showingEditRegistration: Bool
    @Binding var showingEditVehicleDetails: Bool
    @Binding var showingEditInsurance: Bool
    @Binding var showingAddReminder: Bool
    let onSave: (Car) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingEditRegistration) {
                if let car = liveCar {
                    EditRegistrationSheet(car: car, onSave: onSave)
                }
            }
            .sheet(isPresented: $showingEditVehicleDetails) {
                if let car = liveCar {
                    EditVehicleDetailsSheet(car: car, onSave: onSave)
                }
            }
            .sheet(isPresented: $showingEditInsurance) {
                if let car = liveCar {
                    EditInsuranceSheet(car: car, onSave: onSave)
                }
            }
            .sheet(isPresented: $showingAddReminder) {
                if let car = liveCar {
                    AddReminderView(carID: car.id)
                }
            }
    }
}
