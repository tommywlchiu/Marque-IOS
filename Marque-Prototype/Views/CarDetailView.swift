import SwiftUI

struct CarDetailView: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss

    @State var car: Car
    @State private var showingEditDetails = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            // Header section
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text(car.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            // Basic info
            Section(header: Text("Basic Information")) {
                DetailRow(label: "Make", value: car.make)
                DetailRow(label: "Model", value: car.model)
                DetailRow(label: "Year", value: car.year)
            }

            // Registration & Identification
            Section(header: Text("Registration & Identification")) {
                if car.licensePlate.isEmpty && car.vinNumber.isEmpty {
                    Button {
                        showingEditDetails = true
                    } label: {
                        Label("Add License Plate & VIN", systemImage: "plus.circle")
                            .foregroundColor(.accentColor)
                    }
                } else {
                    DetailRow(label: "License Plate", value: car.licensePlate)
                    DetailRow(label: "VIN Number", value: car.vinNumber)
                }
            }

            // Vehicle Details
            Section(header: Text("Vehicle Details")) {
                if !car.hasDetailedInfo && car.licensePlate.isEmpty && car.vinNumber.isEmpty {
                    Button {
                        showingEditDetails = true
                    } label: {
                        Label("Add Vehicle Details", systemImage: "plus.circle")
                            .foregroundColor(.accentColor)
                    }
                } else {
                    DetailRow(label: "Color", value: car.color)
                    DetailRow(label: "Mileage", value: car.mileage)
                    DetailRow(label: "Fuel Type", value: car.fuelType)
                    DetailRow(label: "Transmission", value: car.transmission)
                }
            }

            // Insurance
            Section(header: Text("Insurance")) {
                if car.insuranceProvider.isEmpty && car.insurancePolicyNumber.isEmpty {
                    Button {
                        showingEditDetails = true
                    } label: {
                        Label("Add Insurance Info", systemImage: "plus.circle")
                            .foregroundColor(.accentColor)
                    }
                } else {
                    DetailRow(label: "Provider", value: car.insuranceProvider)
                    DetailRow(label: "Policy Number", value: car.insurancePolicyNumber)
                }
            }

            // Notes
            if !car.notes.isEmpty {
                Section(header: Text("Notes")) {
                    Text(car.notes)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }

            // Delete
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Car", systemImage: "trash")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Car Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEditDetails = true
                }
            }
        }
        .sheet(isPresented: $showingEditDetails) {
            EditCarDetailView(car: $car, onSave: { updatedCar in
                car = updatedCar
                carStore.updateCar(updatedCar)
            })
        }
        .alert("Delete Car", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                carStore.deleteCar(car)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete \(car.displayName)? This action cannot be undone.")
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .foregroundColor(value.isEmpty ? .secondary.opacity(0.5) : .primary)
        }
    }
}

#Preview {
    NavigationStack {
        CarDetailView(car: Car(
            make: "Toyota",
            model: "Camry",
            year: "2024",
            licensePlate: "ABC 1234",
            vinNumber: "1HGBH41JXMN109186"
        ))
        .environmentObject(CarStore())
    }
}
