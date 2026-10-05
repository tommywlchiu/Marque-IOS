import SwiftUI

/// The Garage footer's "Edit Car": the car's identity (make, model, year)
/// and the owner's notes. Everything else has exactly one editor of its own —
/// photos in the Photos tab, plate/VIN/registration and insurance in Wallet,
/// specs/color/mileage in the Garage's Details screen.
struct EditCarDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var car: Car

    var onSave: (Car) -> Void

    @State private var make: String = ""
    @State private var model: String = ""
    @State private var year: String = ""
    @State private var notes: String = ""

    var isFormValid: Bool {
        !make.trimmingCharacters(in: .whitespaces).isEmpty &&
        !model.trimmingCharacters(in: .whitespaces).isEmpty &&
        !year.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Basic Information")) {
                    Picker("Make", selection: $make) {
                        Text("Select a make").tag("")
                        ForEach(CarData.makes, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Model (e.g. Camry, 3 Series)", text: $model)
                        .autocorrectionDisabled()
                    TextField("Year (e.g. 2024)", text: $year)
                        .keyboardType(.numberPad)
                }

                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCar() }
                        .disabled(!isFormValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: populateFields)
        }
    }

    private func saveCar() {
        var updated = car
        updated.make = make
        updated.model = model.trimmingCharacters(in: .whitespaces)
        updated.year = year.trimmingCharacters(in: .whitespaces)
        updated.notes = notes.trimmingCharacters(in: .whitespaces)
        onSave(updated)
        dismiss()
    }

    private func populateFields() {
        make = car.make
        model = car.model
        year = car.year
        notes = car.notes
    }
}
