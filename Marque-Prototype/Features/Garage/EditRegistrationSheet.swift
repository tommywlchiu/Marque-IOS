import SwiftUI

// Focused sheet for editing just a car's registration & identification fields:
// license plate, VIN, and registration expiry date. Presented from the
// Registration section of CarDetailView so the user doesn't have to open the
// full EditCarDetailView form to change a single field.
struct EditRegistrationSheet: View {
    let car: Car
    let onSave: (Car) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var licensePlate: String = ""
    @State private var vinNumber: String = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Identification")) {
                    TextField("License Plate Number", text: $licensePlate)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    TextField("VIN Number", text: $vinNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section(header: Text("Registration")) {
                    Toggle("Expiration", isOn: $hasExpiry.animation())
                        .onChange(of: hasExpiry) { _, isOn in
                            if isOn { NotificationManager.requestPermission() }
                        }
                    if hasExpiry {
                        DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Registration")
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
        licensePlate = car.licensePlate
        vinNumber = car.vinNumber
        if let date = car.registrationExpiryDate {
            hasExpiry = true
            expiryDate = date
        }
    }

    private func save() {
        var updated = car
        updated.licensePlate = licensePlate.trimmingCharacters(in: .whitespaces)
        updated.vinNumber = vinNumber.trimmingCharacters(in: .whitespaces)
        updated.registrationExpiryDate = hasExpiry ? expiryDate : nil
        onSave(updated)
        dismiss()
    }
}
