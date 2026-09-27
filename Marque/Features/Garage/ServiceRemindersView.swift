import SwiftUI

struct ServiceRemindersView: View {
    @EnvironmentObject var carStore: CarStore
    let carID: UUID

    @State private var showingAddReminder = false
    @State private var showingSuggestions = false
    @State private var reminderToEdit: ServiceReminder?
    @State private var reminderToLog: ServiceReminder?
    @State private var showingMaintenanceLimitAlert = false
    @State private var logConfirmation: LogConfirmation?

    private var car: Car? { carStore.cars.first { $0.id == carID } }

    private var reminders: [ServiceReminder] {
        guard let car else { return [] }
        return car.serviceReminders
            .filter { !$0.isCompleted }
            .sorted { sortKey($0, currentMileage: currentMileage) < sortKey($1, currentMileage: currentMileage) }
    }

    private var completed: [ServiceReminder] {
        // Most recently completed first; reminders completed before completedDate
        // existed have no date and go last.
        (car?.serviceReminders.filter(\.isCompleted) ?? []).sorted {
            ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast)
        }
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
        .sheet(item: $reminderToEdit) { reminder in
            AddReminderView(carID: carID, reminder: reminder)
        }
        .sheet(item: $reminderToLog) { reminder in
            logSheet(for: reminder)
        }
        .sheet(isPresented: $showingSuggestions) {
            if let car { SuggestedRemindersSheet(car: car) }
        }
        .alert("Record Limit Reached", isPresented: $showingMaintenanceLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This car has reached the \(CarStore.maxMaintenanceRecords)-record limit. Delete an older record to add a new one.")
        }
        .overlay(alignment: .bottom) {
            if let logConfirmation {
                LogConfirmationBanner(message: logConfirmation.message) {
                    guard let freshCar = car else { return }
                    carStore.undoLogSideEffects(logConfirmation.outcome, for: freshCar)
                    withAnimation { self.logConfirmation = nil }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // Same 5-second confirmation with Undo as the car page's Maintenance Log.
    private func presentConfirmation(_ confirmation: LogConfirmation) {
        withAnimation { logConfirmation = confirmation }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if logConfirmation?.id == confirmation.id {
                withAnimation { logConfirmation = nil }
            }
        }
    }

    // Prefills service type / today's date / current mileage from the
    // reminder being checked off; "Skip" completes it without logging a
    // record. Both actions re-fetch the car fresh at call time (via `car`,
    // a computed property) rather than capturing this closure's snapshot.
    @ViewBuilder
    private func logSheet(for reminder: ServiceReminder) -> some View {
        if let carAtOpen = car {
            AddMaintenanceView(
                prefill: AddMaintenanceView.Prefill(
                    serviceType: reminder.serviceType,
                    date: Date(),
                    mileage: carAtOpen.mileage.replacingOccurrences(of: ",", with: "")
                ),
                onSkip: {
                    guard let freshCar = car else { return }
                    let next = carStore.completeReminder(reminder, in: freshCar)
                    presentConfirmation(LogConfirmation(markedDone: reminder, next: next))
                },
                onSave: { record, receiptImage in
                    guard let freshCar = car else { return }
                    guard freshCar.maintenanceRecords.count < CarStore.maxMaintenanceRecords else {
                        showingMaintenanceLimitAlert = true
                        return
                    }
                    let outcome = carStore.logService(record, for: freshCar, receiptImage: receiptImage)
                    presentConfirmation(LogConfirmation(logged: record, outcome: outcome))
                }
            )
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
                                onComplete: { reminderToLog = reminder },
                                onEdit: { reminderToEdit = reminder }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        }
                        .onDelete(perform: deleteUpcoming)
                    }
                    // Keyed on the filtered array itself so the row smoothly
                    // animates out of Upcoming whenever it changes — covers
                    // both the immediate local tap and the store's async
                    // round trip landing later.
                    .animation(.easeInOut(duration: 0.3), value: reminders)
                }

                if !suggestions.isEmpty {
                    Section {
                        Button {
                            showingSuggestions = true
                        } label: {
                            // No count here — this is the rule-engine's local
                            // estimate, but the sheet may load AI-generated
                            // suggestions instead, which can be a different
                            // number. Showing a number here risked promising
                            // one count and then displaying another.
                            Label("Suggested reminders available", systemImage: "sparkles")
                        }
                    }
                }

                if !completed.isEmpty {
                    Section("Completed") {
                        ForEach(completed) { reminder in
                            ReminderRow(
                                reminder: reminder,
                                currentMileage: currentMileage,
                                onComplete: nil,
                                onEdit: { reminderToEdit = reminder },
                                onRestore: { restore(reminder) }
                            )
                            .opacity(0.7)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    restore(reminder)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.accentColor)
                            }
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
                    Label("Show suggestions", systemImage: "sparkles")
                        .font(.subheadline)
                }
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Actions

    // Un-completes a reminder — for when the user misclicked "done" and wants
    // to bring the reminder back into the Upcoming section.
    private func restore(_ reminder: ServiceReminder) {
        guard var car else { return }
        if let idx = car.serviceReminders.firstIndex(where: { $0.id == reminder.id }) {
            car.serviceReminders[idx].isCompleted = false
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

    // Sort: overdue first, then by soonest trigger (whichever is set).
    //
    // The previous version keyed purely on `daysUntilDue() ?? <bucket
    // fallback>`, so a mileage-only reminder (no dueDate, so daysUntilDue()
    // is always nil) got the same fallback constant as every other
    // mileage-only reminder in its bucket — they clumped together in
    // whatever order the array happened to be in, and in .dueSoon/.upcoming
    // that fallback (999) always sorted them after every date-based reminder
    // regardless of how close their mileage actually was. Normalizing both
    // triggers onto one "soonness" scale (100 miles ~= 1 day — a rough but
    // reasonable stand-in, not meant to be physically exact) and using
    // whichever trigger is set — or the sooner of the two, mirroring
    // ServiceReminder.status()'s own whichever-comes-first semantics — means
    // mileage-only reminders sort by their actual urgency instead.
    private func sortKey(_ r: ServiceReminder, currentMileage: Int) -> Double {
        let dayValue = r.daysUntilDue().map(Double.init)
        let mileValue = r.milesUntilDue(currentMileage: currentMileage).map { Double($0) / 100.0 }
        let soonest = [dayValue, mileValue].compactMap { $0 }.min() ?? .greatestFiniteMagnitude

        switch r.status(currentMileage: currentMileage) {
        case .overdue:  return -1_000_000 + soonest
        case .dueSoon:  return soonest
        case .upcoming: return 1_000 + soonest
        }
    }
}

// MARK: - Reminder Row

private struct ReminderRow: View {
    let reminder: ServiceReminder
    let currentMileage: Int
    let onComplete: (() -> Void)?
    var onEdit: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil

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
                // Opens the log form (prefilled) rather than completing
                // in place — the actual completion happens once that form is
                // saved or explicitly skipped, so no optimistic local state
                // here (a cancelled sheet must leave the row untouched).
                Button(action: onComplete) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log \(reminder.serviceType)")
            } else if let onRestore, reminder.isCompleted {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restore \(reminder.serviceType)")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // A Button inside this HStack (the check/restore control above)
        // consumes its own taps first — SwiftUI hit-tests the deepest
        // interactive view — so this only fires for taps elsewhere on the row.
        .onTapGesture {
            onEdit?()
        }
    }

    private var status: ServiceReminder.Status {
        reminder.status(currentMileage: currentMileage)
    }

    private var statusIcon: some View {
        Group {
            if reminder.isCompleted {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                switch status {
                case .overdue:
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                case .dueSoon:
                    Image(systemName: "clock.fill").foregroundColor(.orange)
                case .upcoming:
                    Image(systemName: "calendar.circle.fill").foregroundColor(.accentColor)
                }
            }
        }
        .font(.title3)
    }

    private var detailText: String {
        // Completed reminders show when they were done, not a due/overdue
        // countdown against a target that no longer applies. completedDate
        // is nil for reminders completed before that field existed.
        if reminder.isCompleted {
            guard let completedDate = reminder.completedDate else { return "Done" }
            return "Done \(completedDate.formatted(date: .abbreviated, time: .omitted))"
        }

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

        // Join with "or" (not "•") when both triggers are set — matches the
        // whichever-first semantics of ServiceReminder.status().
        return parts.joined(separator: " or ")
    }
}

// MARK: - Suggestions Sheet

private struct SuggestedRemindersSheet: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss
    let car: Car

    // Two possible sources: `ai` (Cloud Function-generated, includes reasoning
    // and priority) or `rules` (local engine, used as fallback when the AI
    // call fails or the network is down). Rendering unifies both under the
    // `AIServiceSuggestion` shape — rule-source suggestions get empty
    // reasoning and .medium priority.
    enum Source: Equatable { case ai, rules }

    @State private var suggestions: [AIServiceSuggestion] = []
    @State private var selected: Set<UUID> = []
    @State private var source: Source = .ai
    @State private var isLoading = true
    @State private var loadErrorHint: String?

    private let aiService = AIServiceSuggestionService()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Suggested Reminders")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(selected.count)") { addSelected() }
                            .disabled(selected.isEmpty || isLoading)
                            .fontWeight(.semibold)
                    }
                }
        }
        .task { await load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingState
        } else if suggestions.isEmpty {
            emptyState
        } else {
            List {
                intro
                if let hint = loadErrorHint {
                    Section {
                        Label(hint, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Section {
                    ForEach(suggestions) { suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            isSelected: selected.contains(suggestion.id),
                            currentMileage: ServiceReminderEngine.mileage(from: car.mileage),
                            onTap: { toggle(suggestion.id) }
                        )
                    }
                }
            }
        }
    }

    private var intro: some View {
        Section {
            Text(source == .ai
                 ? "Generated for your \(car.displayName) based on its specs and service history."
                 : "Based on your service history and standard intervals.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .listRowBackground(Color.clear)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Analyzing your service history…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        MarqueEmptyState(
            icon: "checkmark.seal",
            title: "You're All Set",
            subtitle: "No new suggestions right now — nothing appears due based on your history."
        )
    }

    // MARK: - Load

    private func load() async {
        // Skip re-loading if we already have suggestions (guards against
        // .task firing again on view refresh).
        guard suggestions.isEmpty else { return }

        do {
            let ai = try await aiService.suggest(for: car)
            if ai.isEmpty {
                // Cover the case where the model returns no suggestions — use
                // the rule engine so we don't leave the user with a bare sheet.
                await MainActor.run {
                    self.applyFallback(hint: nil)
                    self.isLoading = false
                }
                return
            }
            await MainActor.run {
                self.suggestions = ai
                self.selected = Set(ai.map(\.id))
                self.source = .ai
                self.isLoading = false
            }
        } catch let error as AIServiceSuggestionService.SuggestionError {
            await MainActor.run {
                self.applyFallback(hint: error.errorDescription)
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.applyFallback(hint: nil)
                self.isLoading = false
            }
        }
    }

    private func applyFallback(hint: String?) {
        let fallback = ServiceReminderEngine.suggest(for: car)
            .map(AIServiceSuggestion.init(fallbackFrom:))
        suggestions = fallback
        selected = Set(fallback.map(\.id))
        source = .rules
        loadErrorHint = hint
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func addSelected() {
        var updated = car
        for suggestion in suggestions where selected.contains(suggestion.id) {
            updated.serviceReminders.append(suggestion.asReminder())
        }
        carStore.updateCar(updated)
        dismiss()
    }
}

// Row for one suggestion. Shows priority (if reasoning is present — i.e.,
// AI-sourced) and the reasoning line so the user knows WHY it's here.
private struct SuggestionRow: View {
    let suggestion: AIServiceSuggestion
    let isSelected: Bool
    let currentMileage: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(suggestion.serviceType)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.primary)
                            if !suggestion.reasoning.isEmpty {
                                priorityBadge
                            }
                        }
                        Text(dueSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                if !suggestion.reasoning.isEmpty {
                    Text(suggestion.reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.85))
                        .padding(.leading, 32)  // aligns under the text column
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var priorityBadge: some View {
        Text(suggestion.priority.rawValue.capitalized)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundColor(priorityColor)
            .background(priorityColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var priorityColor: Color {
        switch suggestion.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    private var dueSummary: String {
        var parts: [String] = []
        if let date = suggestion.dueDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
            if days < 0 { parts.append("\(-days) days overdue") }
            else if days == 0 { parts.append("Due today") }
            else { parts.append("Due in \(days) days") }
        }
        if let miles = suggestion.dueMileage {
            let delta = miles - currentMileage
            if delta < 0 { parts.append("\(-delta) mi past due") }
            else { parts.append("in \(delta) mi") }
        }
        // "or" — whichever comes first triggers the reminder.
        return parts.isEmpty ? "No specific due date" : parts.joined(separator: " or ")
    }
}
