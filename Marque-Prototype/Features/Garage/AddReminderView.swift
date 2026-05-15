import SwiftUI

struct AddReminderView: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss

    let carID: UUID

    @State private var serviceType: String = MaintenanceRecord.serviceTypes.first ?? ""
    @State private var customServiceType = ""
    @State private var notes = ""
    @State private var useDateTrigger = true
    @State private var dueDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var useMileageTrigger = false
    @State private var dueMileageText = ""

    private var resolvedServiceType: String {
        serviceType == "Other" ? customServiceType.trimmingCharacters(in: .whitespaces) : serviceType
    }

    private var canSave: Bool {
        !resolvedServiceType.isEmpty && (useDateTrigger || useMileageTrigger)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    Picker("Type", selection: $serviceType) {
                        ForEach(MaintenanceRecord.serviceTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    if serviceType == "Other" {
                        TextField("Service name", text: $customServiceType)
                            .autocorrectionDisabled()
                    }
                }

                Section("When") {
                    Toggle("Set due date", isOn: $useDateTrigger.animation())
                    if useDateTrigger {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }

                    Toggle("Set due mileage", isOn: $useMileageTrigger.animation())
                    if useMileageTrigger {
                        TextField("Due mileage (e.g. 50000)", text: $dueMileageText)
                            .keyboardType(.numberPad)
                    }
                }

                if !useDateTrigger && !useMileageTrigger {
                    Section {
                        Label("Enable at least one trigger to save this reminder.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        guard var car = carStore.cars.first(where: { $0.id == carID }) else { return }

        let reminder = ServiceReminder(
            serviceType: resolvedServiceType,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: useDateTrigger ? dueDate : nil,
            dueMileage: useMileageTrigger ? Int(dueMileageText.replacingOccurrences(of: ",", with: "")) : nil
        )

        car.serviceReminders.append(reminder)
        carStore.updateCar(car)
        dismiss()
    }
}
