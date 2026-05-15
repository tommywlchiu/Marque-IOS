import SwiftUI

struct ServiceRemindersView: View {
    @EnvironmentObject var carStore: CarStore
    let carID: UUID

    @State private var showingAddReminder = false
    @State private var showingSuggestions = false

    private var car: Car? { carStore.cars.first { $0.id == carID } }

    private var reminders: [ServiceReminder] {
        guard let car else { return [] }
        return car.serviceReminders
            .filter { !$0.isCompleted }
            .sorted { sortKey($0, currentMileage: currentMileage) < sortKey($1, currentMileage: currentMileage) }
    }

    private var completed: [ServiceReminder] {
        car?.serviceReminders.filter(\.isCompleted) ?? []
    }

    private var currentMileage: Int {
        ServiceReminderEngine.mileage(from: car?.mileage ?? "")
    }

    private var suggestions: [ServiceReminder] {
        guard let car else { return [] }
        return ServiceReminderEngine.suggest(for: car)
    }

    var body: some View {
        Group {
            if let car {
                content(for: car)
            } else {
                MarqueEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Car not found",
                    subtitle: "This car may have been deleted."
                )
            }
        }
        .navigationTitle("Service Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddReminder = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddReminder) {
            if let car { AddReminderView(carID: car.id) }
        }
        .sheet(isPresented: $showingSuggestions) {
            if let car { SuggestedRemindersSheet(car: car) }
        }
    }

    @ViewBuilder
    private func content(for car: Car) -> some View {
        if reminders.isEmpty && completed.isEmpty {
            emptyState(for: car)
        } else {
            List {
                if !reminders.isEmpty {
                    Section("Upcoming") {
                        ForEach(reminders) { reminder in
                            ReminderRow(
                                reminder: reminder,
                                currentMileage: currentMileage,
                                onComplete: { complete(reminder) }
                            )
                        }
                        .onDelete(perform: deleteUpcoming)
                    }
                }

                if !suggestions.isEmpty {
                    Section {
                        Button {
                            showingSuggestions = true
                        } label: {
                            Label("\(suggestions.count) suggested reminders", systemImage: "sparkles")
                        }
                    }
                }

                if !completed.isEmpty {
                    Section("Completed") {
                        ForEach(completed) { reminder in
                            ReminderRow(reminder: reminder, currentMileage: currentMileage, onComplete: nil)
                                .opacity(0.55)
                        }
                        .onDelete(perform: deleteCompleted)
                    }
                }
            }
        }
    }

    private func emptyState(for car: Car) -> some View {
        VStack(spacing: 24) {
            MarqueEmptyState(
                icon: "wrench.and.screwdriver",
                title: "No Reminders Yet",
                subtitle: "Track upcoming services so nothing slips.",
                actionTitle: "Add Reminder",
                action: { showingAddReminder = true }
            )

            if !suggestions.isEmpty {
                Button {
                    showingSuggestions = true
                } label: {
                    Label("Show \(suggestions.count) suggestions", systemImage: "sparkles")
                        .font(.subheadline)
                }
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func complete(_ reminder: ServiceReminder) {
        guard var car else { return }
        if let idx = car.serviceReminders.firstIndex(where: { $0.id == reminder.id }) {
            car.serviceReminders[idx].isCompleted = true
            carStore.updateCar(car)
        }
    }

    private func deleteUpcoming(at offsets: IndexSet) {
        guard var car else { return }
        let toDelete = offsets.map { reminders[$0].id }
        car.serviceReminders.removeAll { toDelete.contains($0.id) }
        carStore.updateCar(car)
    }

    private func deleteCompleted(at offsets: IndexSet) {
        guard var car else { return }
        let toDelete = offsets.map { completed[$0].id }
        car.serviceReminders.removeAll { toDelete.contains($0.id) }
        carStore.updateCar(car)
    }

    // Sort: overdue first, then by soonest due date or due mileage.
    private func sortKey(_ r: ServiceReminder, currentMileage: Int) -> Double {
        switch r.status(currentMileage: currentMileage) {
        case .overdue:  return -1_000_000 + Double(r.daysUntilDue() ?? 0)
        case .dueSoon:  return Double(r.daysUntilDue() ?? 999)
        case .upcoming: return 1_000 + Double(r.daysUntilDue() ?? 999)
        }
    }
}

// MARK: - Reminder Row

private struct ReminderRow: View {
    let reminder: ServiceReminder
    let currentMileage: Int
    let onComplete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.serviceType)
                    .font(.subheadline).fontWeight(.semibold)

                Text(detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !reminder.notes.isEmpty {
                    Text(reminder.notes)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            if let onComplete, !reminder.isCompleted {
                Button(action: onComplete) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var status: ServiceReminder.Status {
        reminder.status(currentMileage: currentMileage)
    }

    private var statusIcon: some View {
        Group {
            switch status {
            case .overdue:
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
            case .dueSoon:
                Image(systemName: "clock.fill").foregroundColor(.orange)
            case .upcoming:
                Image(systemName: "calendar.circle.fill").foregroundColor(.accentColor)
            }
        }
        .font(.title3)
    }

    private var detailText: String {
        var parts: [String] = []

        if let days = reminder.daysUntilDue() {
            if days < 0 { parts.append("\(-days) days overdue") }
            else if days == 0 { parts.append("Due today") }
            else { parts.append("Due in \(days) days") }
        }

        if let miles = reminder.milesUntilDue(currentMileage: currentMileage) {
            if miles < 0 { parts.append("\(-miles) mi past due") }
            else { parts.append("\(miles) mi to go") }
        }

        return parts.joined(separator: " • ")
    }
}

// MARK: - Suggestions Sheet

private struct SuggestedRemindersSheet: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss
    let car: Car

    @State private var selected: Set<UUID> = []

    private var suggestions: [ServiceReminder] {
        ServiceReminderEngine.suggest(for: car)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Based on your service history and standard intervals.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(suggestions) { reminder in
                        Button { toggle(reminder.id) } label: {
                            HStack {
                                Image(systemName: selected.contains(reminder.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(.accentColor)
                                ReminderRow(
                                    reminder: reminder,
                                    currentMileage: ServiceReminderEngine.mileage(from: car.mileage),
                                    onComplete: nil
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Suggested Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") { addSelected() }
                        .disabled(selected.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { selected = Set(suggestions.map(\.id)) }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func addSelected() {
        var updated = car
        for s in suggestions where selected.contains(s.id) {
            updated.serviceReminders.append(s)
        }
        carStore.updateCar(updated)
        dismiss()
    }
}
