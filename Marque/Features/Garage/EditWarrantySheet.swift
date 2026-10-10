import SwiftUI

/// Focused sheet for editing a car's warranty fields: who covers it, what
/// kind, and (since 2026-10-10) an optional expiry that drives the same
/// attention-card badge, status line and 30d/7d/on-day notifications as
/// Insurance/Registration. No document scanner — warranty paperwork isn't a
/// standardized card like an insurance ID. Mirrors the same shape/save
/// pattern as EditInsuranceSheet/EditRegistrationSheet.
struct EditWarrantySheet: View {
    let car: Car
    let onSave: (Car) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var provider: String = ""
    @State private var type: String = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date()

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
                    Toggle("Expiration", isOn: $hasExpiry.animation())
                        .onChange(of: hasExpiry) { _, isOn in
                            if isOn { NotificationManager.requestPermission() }
                        }
                    if hasExpiry {
                        DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
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
        if let date = car.warrantyExpiryDate {
            hasExpiry = true
            expiryDate = date
        }
    }

    private func save() {
        var updated = car
        updated.warrantyProvider = provider.trimmingCharacters(in: .whitespaces)
        updated.warrantyType = type
        updated.warrantyExpiryDate = hasExpiry ? expiryDate : nil
        onSave(updated)
        dismiss()
    }
}
