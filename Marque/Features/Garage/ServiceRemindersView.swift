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
                            Label("\(suggestions.count) suggested reminders", systemImage: "sparkles")
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
            // Success haptic on completion only — restoring isn't a success moment.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeInOut(duration: 0.3)) {
                carStore.updateCar(car)
            }
        }
    }

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
    var onRestore: (() -> Void)? = nil

    // Optimistic, row-local "just completed" flag. Drives an immediate
    // checkmark pop + strikethrough + fade the moment the user taps, rather
    // than waiting on carStore.updateCar's async Firestore round trip before
    // showing any feedback. The row itself is removed from "Upcoming" a
    // moment later (see the `.animation(value: reminders)` on the List)
    // once that write lands and `car.serviceReminders` actually updates.
    @State private var isCompleting = false

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.serviceType)
                    .font(.subheadline).fontWeight(.semibold)
                    .strikethrough(isCompleting, color: .secondary)
                    .foregroundColor(isCompleting ? .secondary : .primary)

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
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                        isCompleting = true
                    }
                    onComplete()
                } label: {
                    Image(systemName: isCompleting ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.title3)
                        .foregroundColor(isCompleting ? .green : .accentColor)
                        .scaleEffect(isCompleting ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isCompleting)
                .accessibilityLabel("Mark \(reminder.serviceType) complete")
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
        .opacity(isCompleting ? 0.55 : 1)
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
