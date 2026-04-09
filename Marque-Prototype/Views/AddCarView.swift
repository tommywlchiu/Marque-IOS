import SwiftUI

struct AddCarView: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss

    @State private var make = ""
    @State private var model = ""
    @State private var year = ""

    var isFormValid: Bool {
        !make.trimmingCharacters(in: .whitespaces).isEmpty &&
        !model.trimmingCharacters(in: .whitespaces).isEmpty &&
        !year.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Car Information")) {
                    TextField("Make (e.g. Toyota, BMW)", text: $make)
                        .autocorrectionDisabled()

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
            .navigationTitle("Add a Car")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let car = Car(
                            make: make.trimmingCharacters(in: .whitespaces),
                            model: model.trimmingCharacters(in: .whitespaces),
                            year: year.trimmingCharacters(in: .whitespaces)
                        )
                        carStore.addCar(car)
                        dismiss()
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    AddCarView()
        .environmentObject(CarStore())
}
