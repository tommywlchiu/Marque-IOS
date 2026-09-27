import SwiftUI

struct AddReminderView: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss

    let carID: UUID
    private let editingReminder: ServiceReminder?

    @State private var serviceType: String = MaintenanceRecord.serviceTypes.first ?? ""
    @State private var customServiceType = ""
    @State private var notes = ""
    @State private var useDateTrigger = true
    @State private var dueDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var useMileageTrigger = false
    @State private var dueMileageText = ""

    private var isEditing: Bool { editingReminder != nil }

    /// Add mode.
    init(carID: UUID) {
        self.carID = carID
        self.editingReminder = nil
    }

    /// Edit mode — prefills every field from the existing reminder.
    init(carID: UUID, reminder: ServiceReminder) {
        self.carID = carID
        self.editingReminder = reminder

        let isPreset = MaintenanceRecord.serviceTypes.contains(reminder.serviceType)
        _serviceType = State(initialValue: isPreset ? reminder.serviceType : "Other")
        _customServiceType = State(initialValue: isPreset ? "" : reminder.serviceType)
        _notes = State(initialValue: reminder.notes)
        _useDateTrigger = State(initialValue: reminder.dueDate != nil)
        _dueDate = State(initialValue: reminder.dueDate ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date())
        _useMileageTrigger = State(initialValue: reminder.dueMileage != nil)
        _dueMileageText = State(initialValue: reminder.dueMileage.map(String.init) ?? "")
    }

    private var car: Car? {
        carStore.cars.first(where: { $0.id == carID })
    }

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

                Section {
                    Toggle("Set due date", isOn: $useDateTrigger.animation())
                    if useDateTrigger {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }

                    Toggle("Set due mileage", isOn: $useMileageTrigger.animation())
                    if useMileageTrigger {
                        TextField("Due mileage (e.g. 50000)", text: $dueMileageText)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Text("When")
                } footer: {
                    if useDateTrigger && useMileageTrigger {
                        Text("Whichever comes first will trigger the reminder.")
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
            .navigationTitle(isEditing ? "Edit Reminder" : "Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            // Only auto-fill defaults on first appearance in Add mode — in
            // Edit mode the initial values are the reminder's own saved
            // values (set in `init(carID:reminder:)`), and this would
            // otherwise clobber them the instant the sheet opens.
            .onAppear {
                if !isEditing { configureDefaults(for: serviceType) }
            }
            .onChange(of: serviceType) { _, newType in configureDefaults(for: newType) }
        }
    }

    // Auto-configures both triggers + their values based on the picked service
    // type. Time-driven services get a date-only default; mileage-driven get
    // mileage-only; safety/engine-critical get both.
    //
    // Mileage is anchored to the last service of this type when available,
    // otherwise to current mileage; if neither is set, we skip the mileage
    // trigger entirely (falling back to a date-only default so `canSave`
    // still evaluates true).
    //
    // Trade-off: re-runs on every picker change, which will overwrite manual
    // tweaks the user made before switching service types. Acceptable — the
    // typical flow is "pick service, accept defaults."
    private func configureDefaults(for type: String) {
        guard let car else { return }

        let months: Int?
        let miles: Int?
        if let interval = ServiceReminderEngine.interval(for: type) {
            months = interval.months
            miles = interval.miles
        } else {
            // Unknown service type (e.g., "Other") — sensible default of
            // date-only 6 months. User can adjust or add mileage manually.
            months = 6
            miles = nil
        }

        // Date trigger
        if let m = months {
            useDateTrigger = true
            let anchor = ServiceReminderEngine.dateAnchor(for: type, car: car)
            dueDate = Calendar.current.date(byAdding: .month, value: m, to: anchor) ?? Date()
        } else {
            useDateTrigger = false
        }

        // Mileage trigger — only if we have both a known interval AND a
        // mileage anchor to compute the next occurrence from.
        if let mi = miles, let anchor = ServiceReminderEngine.mileageAnchor(for: type, car: car) {
            useMileageTrigger = true
            dueMileageText = String(ServiceReminderEngine.roundedMileage(anchor + mi))
        } else {
            useMileageTrigger = false
            dueMileageText = ""
        }

        // Safety net: if we ended up with neither trigger enabled (mileage-
        // only service with no mileage anchor), flip on the date trigger with
        // a 6-month default so the form remains submittable.
        if !useDateTrigger && !useMileageTrigger {
            useDateTrigger = true
            dueDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
        }
    }

    private func save() {
        guard let car = carStore.cars.first(where: { $0.id == carID }) else { return }

        let dueDateValue = useDateTrigger ? dueDate : nil
        let dueMileageValue = useMileageTrigger ? Int(dueMileageText.replacingOccurrences(of: ",", with: "")) : nil

        if var editingReminder {
            editingReminder.serviceType = resolvedServiceType
            editingReminder.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            editingReminder.dueDate = dueDateValue
            editingReminder.dueMileage = dueMileageValue
            carStore.updateReminder(editingReminder, in: car)
        } else {
            let reminder = ServiceReminder(
                serviceType: resolvedServiceType,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                dueDate: dueDateValue,
                dueMileage: dueMileageValue
            )
            var updated = car
            updated.serviceReminders.append(reminder)
            carStore.updateCar(updated)
        }
        dismiss()
    }
}
