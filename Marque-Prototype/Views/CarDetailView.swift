import SwiftUI

struct CarDetailView: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss

    @State var car: Car
    @State private var showingEditDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var showingAddMaintenance = false

    var body: some View {
        List {
            photoHeaderSection

            Section(header: Text("Basic Information")) {
                DetailRow(label: "Make", value: car.make)
                DetailRow(label: "Model", value: car.model)
                DetailRow(label: "Year", value: car.year)
            }

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

            if !car.notes.isEmpty {
                Section(header: Text("Notes")) {
                    Text(car.notes)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }

            maintenanceSection

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
        .sheet(isPresented: $showingAddMaintenance) {
            AddMaintenanceView { record in
                car.maintenanceRecords.append(record)
                carStore.updateCar(car)
            }
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

    private var photoHeaderSection: some View {
        Section {
            VStack(spacing: 12) {
                if let fileName = car.photoFileName,
                   let uiImage = ImageManager.loadImage(fileName: fileName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.08))
                            .frame(height: 120)

                        VStack(spacing: 8) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.accentColor.opacity(0.4))

                            Text("Tap Edit to add a photo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Text(car.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var maintenanceSection: some View {
        Section(header: HStack {
            Text("Maintenance Log")
            Spacer()
            Button {
                showingAddMaintenance = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline)
            }
        }) {
            if car.sortedMaintenanceRecords.isEmpty {
                Button {
                    showingAddMaintenance = true
                } label: {
                    Label("Add Service Record", systemImage: "wrench.and.screwdriver")
                        .foregroundColor(.accentColor)
                }
            } else {
                ForEach(car.sortedMaintenanceRecords) { record in
                    MaintenanceRowView(record: record)
                }
                .onDelete { offsets in
                    let sorted = car.sortedMaintenanceRecords
                    for index in offsets {
                        let record = sorted[index]
                        car.maintenanceRecords.removeAll { $0.id == record.id }
                    }
                    carStore.updateCar(car)
                }
            }
        }
    }
}

struct MaintenanceRowView: View {
    let record: MaintenanceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.serviceType)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if !record.cost.isEmpty {
                    Text("$\(record.cost)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
            }

            HStack(spacing: 12) {
                Text(record.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !record.mileage.isEmpty {
                    Text("\(record.mileage) mi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !record.shop.isEmpty {
                    Text(record.shop)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
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
            vinNumber: "1HGBH41JXMN109186",
            maintenanceRecords: [
                MaintenanceRecord(serviceType: "Oil Change", date: Date(), mileage: "25000", cost: "45", shop: "Jiffy Lube")
            ]
        ))
        .environmentObject(CarStore())
    }
}
