import SwiftUI

struct AddMaintenanceView: View {
    @Environment(\.dismiss) var dismiss

    var onSave: (MaintenanceRecord) -> Void

    @State private var serviceType = ""
    @State private var date = Date()
    @State private var mileage = ""
    @State private var cost = ""
    @State private var shop = ""
    @State private var notes = ""

    var isFormValid: Bool {
        !serviceType.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Service")) {
                    Picker("Service Type", selection: $serviceType) {
                        Text("Select a service").tag("")
                        ForEach(MaintenanceRecord.serviceTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section(header: Text("Details")) {
                    TextField("Mileage at service", text: $mileage)
                        .keyboardType(.numberPad)

                    HStack {
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("Cost", text: $cost)
                            .keyboardType(.decimalPad)
                    }

                    TextField("Shop / Mechanic", text: $shop)
                }

                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add Service Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let record = MaintenanceRecord(
                            serviceType: serviceType,
                            date: date,
                            mileage: mileage.trimmingCharacters(in: .whitespaces),
                            cost: cost.trimmingCharacters(in: .whitespaces),
                            shop: shop.trimmingCharacters(in: .whitespaces),
                            notes: notes.trimmingCharacters(in: .whitespaces)
                        )
                        onSave(record)
                        dismiss()
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
