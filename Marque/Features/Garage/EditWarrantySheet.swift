import SwiftUI

/// Focused sheet for editing just a car's warranty fields: who covers it and
/// what kind. No expiry tracking (owner decision — unlike Insurance/
/// Registration, a warranty here doesn't drive attention-card badges or
/// notifications) and no document scanner — warranty paperwork isn't a
/// standardized card like an insurance ID. Mirrors the same shape/save
/// pattern as EditInsuranceSheet/EditRegistrationSheet.
struct EditWarrantySheet: View {
    let car: Car
    let onSave: (Car) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var provider: String = ""
    @State private var type: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Warranty")) {
                    TextField("Provider (e.g. BMW, CarMax, Endurance)", text: $provider)
                        .autocorrectionDisabled()
                    Picker("Type", selection: $type) {
                        Text("Select a type").tag("")
                        ForEach(CarData.warrantyTypes, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .navigationTitle("Warranty")
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
        provider = car.warrantyProvider
        type = car.warrantyType
    }

    private func save() {
        var updated = car
        updated.warrantyProvider = provider.trimmingCharacters(in: .whitespaces)
        updated.warrantyType = type
        onSave(updated)
        dismiss()
    }
}
