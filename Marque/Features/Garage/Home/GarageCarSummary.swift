import SwiftUI

// MARK: - Reminder urgency (shared with ServiceRemindersView)

/// Ordering and wording for open service reminders. Moved out of
/// `ServiceRemindersView` so the Reminders screen and the Garage home's
/// status line / attention card rank and describe reminders identically.
enum ReminderUrgency {
    /// Sort: overdue first, then by soonest trigger (whichever is set).
    ///
    /// Both triggers are normalized onto one "soonness" scale (100 miles ~=
    /// 1 day — a rough stand-in, not meant to be physically exact), using
    /// whichever is set, or the sooner of the two, mirroring
    /// `ServiceReminder.status()`'s whichever-comes-first semantics. Keying
    /// on days alone clumped every mileage-only reminder together after all
    /// date-based ones regardless of how close their mileage actually was.
    static func sortKey(_ r: ServiceReminder, currentMileage: Int, today: Date = Date()) -> Double {
        let soonest = soonness(r, currentMileage: currentMileage, today: today) ?? .greatestFiniteMagnitude
        switch r.status(currentMileage: currentMileage, today: today) {
        case .overdue:  return -1_000_000 + soonest
        case .dueSoon:  return soonest
        case .upcoming: return 1_000 + soonest
        }
    }

    /// Days until the sooner trigger (miles / 100 for mileage). nil if neither is set.
    static func soonness(_ r: ServiceReminder, currentMileage: Int, today: Date = Date()) -> Double? {
        let dayValue = r.daysUntilDue(today: today).map(Double.init)
        let mileValue = r.milesUntilDue(currentMileage: currentMileage).map { Double($0) / 100.0 }
        return [dayValue, mileValue].compactMap { $0 }.min()
    }

    /// Open (not completed) reminders, most urgent first.
    static func openReminders(of car: Car, today: Date = Date()) -> [ServiceReminder] {
        let mileage = ServiceReminderEngine.mileage(from: car.mileage)
        return car.serviceReminders
            .filter { !$0.isCompleted }
            .sorted { sortKey($0, currentMileage: mileage, today: today) < sortKey($1, currentMileage: mileage, today: today) }
    }

    /// "Due in 12 days or 800 mi to go" / "3 days overdue" / "Done Mar 3".
    static func detailText(_ reminder: ServiceReminder, currentMileage: Int) -> String {
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
        // "or", not "•", when both triggers are set — matches the
        // whichever-first semantics of ServiceReminder.status().
        return parts.joined(separator: " or ")
    }

    /// Short headline for one reminder: "Oil Change overdue",
    /// "Oil Change due in 1,200 mi", "Oil Change due Mar 3".
    static func headline(_ r: ServiceReminder, currentMileage: Int, today: Date = Date()) -> String {
        if r.status(currentMileage: currentMileage, today: today) == .overdue {
            return "\(r.serviceType) overdue"
        }
        let days = r.daysUntilDue(today: today)
        let miles = r.milesUntilDue(currentMileage: currentMileage)
        // Whichever trigger comes first, on the same 100 mi ~= 1 day scale.
        if let miles, days.map({ Double(miles) / 100.0 < Double($0) }) ?? true {
            return "\(r.serviceType) due in \(miles.formatted()) mi"
        }
        if let days, let date = r.dueDate {
            if days == 0 { return "\(r.serviceType) due today" }
            if days == 1 { return "\(r.serviceType) due tomorrow" }
            return "\(r.serviceType) due \(GarageSummary.shortDate(date, today: today))"
        }
        return r.serviceType
    }
}

// MARK: - Garage home summaries

/// Everything the Garage home derives from a `Car` for display: the status
/// line, the attention card and each row's live subtitle. Pure functions of
/// the car (and today), so they're cheap to recompute on every render.
enum GarageSummary {
    /// The status line and attention card look this far ahead.
    static let statusLookaheadDays = 60
    /// Mileage-only reminders count as "coming up" within this many miles.
    static let statusLookaheadMiles = 3_000

    static func shortDate(_ date: Date, today: Date = Date()) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: today, toGranularity: .year)
        return sameYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func mileageText(_ car: Car) -> String? {
        car.mileageValue.map { "\($0.formatted()) mi" }
    }

    // MARK: Status line

    struct StatusLine {
        let text: String
        let needsAttention: Bool
    }

    /// The single most urgent upcoming item: an overdue reminder, an expired
    /// document, then whatever comes soonest of reminders and registration /
    /// insurance expiry within `statusLookaheadDays`; else "All caught up".
    static func statusLine(for car: Car, today: Date = Date()) -> StatusLine {
        let mileage = ServiceReminderEngine.mileage(from: car.mileage)
        let reminders = ReminderUrgency.openReminders(of: car, today: today)

        if let overdue = reminders.first(where: { $0.status(currentMileage: mileage, today: today) == .overdue }) {
            return StatusLine(text: ReminderUrgency.headline(overdue, currentMileage: mileage, today: today), needsAttention: true)
        }
        if car.isRegistrationExpired { return StatusLine(text: "Registration expired", needsAttention: true) }
        if car.isInsuranceExpired { return StatusLine(text: "Insurance expired", needsAttention: true) }

        // Candidates within the look-ahead window, ranked by days-away.
        var candidates: [(soonness: Double, line: StatusLine)] = []
        if let next = reminders.first, let soonness = ReminderUrgency.soonness(next, currentMileage: mileage, today: today),
           isWithinLookahead(next, currentMileage: mileage, today: today) {
            let dueSoon = next.status(currentMileage: mileage, today: today) == .dueSoon
            candidates.append((soonness, StatusLine(text: ReminderUrgency.headline(next, currentMileage: mileage, today: today), needsAttention: dueSoon)))
        }
        for (label, date) in [("Registration", car.registrationExpiryDate), ("Insurance", car.insuranceExpiryDate)] {
            guard let date, let days = daysUntil(date, today: today), days <= statusLookaheadDays else { continue }
            candidates.append((Double(days), StatusLine(text: expiryPhrase(label, days: days, date: date, today: today), needsAttention: days <= 30)))
        }
        if let best = candidates.min(by: { $0.soonness < $1.soonness }) {
            return best.line
        }
        return StatusLine(text: "All caught up", needsAttention: false)
    }

    private static func isWithinLookahead(_ r: ServiceReminder, currentMileage: Int, today: Date) -> Bool {
        if r.status(currentMileage: currentMileage, today: today) != .upcoming { return true }
        if let days = r.daysUntilDue(today: today), days <= statusLookaheadDays { return true }
        if let miles = r.milesUntilDue(currentMileage: currentMileage), miles <= statusLookaheadMiles { return true }
        return false
    }

    private static func daysUntil(_ date: Date, today: Date) -> Int? {
        Calendar.current.dateComponents([.day], from: today, to: date).day
    }

    private static func expiryPhrase(_ label: String, days: Int, date: Date, today: Date) -> String {
        switch days {
        case ..<0: return "\(label) expired"
        case 0: return "\(label) expires today"
        case 1: return "\(label) expires tomorrow"
        default: return "\(label) expires \(shortDate(date, today: today))"
        }
    }

    // MARK: Attention card

    enum AttentionTarget: Hashable {
        case documents
        case reminders
        case publicSharing
    }

    struct AttentionItem: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
        let isUrgent: Bool
        let target: AttentionTarget
    }

    /// At most this many reminder rows; the rest fold into one "N more" row.
    static let maxReminderAttentionRows = 3

    /// Expired / expiring-within-30-days documents, overdue / due-soon
    /// reminders, and the one-time sharing review. Empty when nothing needs
    /// the owner (the card is then not rendered at all).
    static func attentionItems(for car: Car, today: Date = Date()) -> [AttentionItem] {
        var items: [AttentionItem] = []

        func document(_ label: String, date: Date?, expired: Bool, soon: Bool) {
            guard let date, expired || soon else { return }
            let days = daysUntil(date, today: today) ?? 0
            let subtitle: String
            if expired {
                subtitle = "Expired \(shortDate(date, today: today))"
            } else if days == 0 {
                subtitle = "Expires today"
            } else {
                subtitle = "Expires in \(days) day\(days == 1 ? "" : "s") · \(shortDate(date, today: today))"
            }
            items.append(AttentionItem(
                id: label,
                icon: expired ? "exclamationmark.triangle" : "doc.text",
                title: expired ? "\(label) expired" : "\(label) expiring",
                subtitle: subtitle,
                isUrgent: expired,
                target: .documents
            ))
        }
        document("Registration", date: car.registrationExpiryDate,
                 expired: car.isRegistrationExpired, soon: car.isRegistrationExpiringSoon)
        document("Insurance", date: car.insuranceExpiryDate,
                 expired: car.isInsuranceExpired, soon: car.isInsuranceExpiringSoon)

        let mileage = ServiceReminderEngine.mileage(from: car.mileage)
        let due = ReminderUrgency.openReminders(of: car, today: today)
            .filter { $0.status(currentMileage: mileage, today: today) != .upcoming }
        for reminder in due.prefix(maxReminderAttentionRows) {
            let overdue = reminder.status(currentMileage: mileage, today: today) == .overdue
            items.append(AttentionItem(
                id: "reminder-\(reminder.id.uuidString)",
                icon: "wrench.and.screwdriver",
                title: overdue ? "\(reminder.serviceType) overdue" : "\(reminder.serviceType) due soon",
                subtitle: ReminderUrgency.detailText(reminder, currentMileage: mileage),
                isUrgent: overdue,
                target: .reminders
            ))
        }
        if due.count > maxReminderAttentionRows {
            let more = due.count - maxReminderAttentionRows
            items.append(AttentionItem(
                id: "reminders-more",
                icon: "list.bullet",
                title: "\(more) more service\(more == 1 ? "" : "s") due",
                subtitle: "See all reminders",
                isUrgent: false,
                target: .reminders
            ))
        }

        if CarSharingSummary.needsReview(car) {
            items.append(AttentionItem(
                id: "sharing-review",
                icon: "eye.trianglebadge.exclamationmark",
                title: "Choose what's shared",
                subtitle: "Hide mileage, notes and more from your public page",
                isUrgent: false,
                target: .publicSharing
            ))
        }
        return items
    }

    // MARK: Row subtitles

    static func serviceHistorySubtitle(_ car: Car, today: Date = Date()) -> String {
        let records = car.sortedMaintenanceRecords
        guard let last = records.first else { return "No records yet" }
        let count = "\(records.count) record\(records.count == 1 ? "" : "s")"
        return "\(count) · last \(shortDate(last.date, today: today))"
    }

    static func remindersSubtitle(_ car: Car, today: Date = Date()) -> String {
        let mileage = ServiceReminderEngine.mileage(from: car.mileage)
        let open = car.serviceReminders.filter { !$0.isCompleted }
        guard !open.isEmpty else { return car.serviceReminders.isEmpty ? "None set" : "All done" }
        let overdue = open.filter { $0.status(currentMileage: mileage, today: today) == .overdue }.count
        let upcoming = "\(open.count) upcoming"
        return overdue > 0 ? "\(upcoming) · \(overdue) overdue" : upcoming
    }

    static func remindersNeedAttention(_ car: Car, today: Date = Date()) -> Bool {
        let mileage = ServiceReminderEngine.mileage(from: car.mileage)
        return car.serviceReminders.contains { !$0.isCompleted && $0.status(currentMileage: mileage, today: today) == .overdue }
    }

    static func modsSubtitle(_ car: Car) -> String {
        car.mods.isEmpty ? "Add your first mod" : "\(car.mods.count) mod\(car.mods.count == 1 ? "" : "s")"
    }

    static func expensesSubtitle(_ car: Car) -> String {
        guard car.totalExpenses > 0 else { return "No expenses yet" }
        let year = car.expenses(in: .year)
        return "\(year.formatted(.currency(code: "USD"))) in the last 12 months"
    }

    static func valueSubtitle(_ car: Car) -> String {
        guard let value = car.estimatedValue else { return "Not estimated yet" }
        let amount = value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return "\(amount) · \(car.valueSource == .ai ? "AI estimate" : "Your estimate")"
    }

    static func engineSoundSubtitle(_ car: Car) -> String {
        let hasClip = car.engineSoundFileName != nil || !(car.engineSoundURL ?? "").isEmpty
        guard hasClip else { return "Not recorded" }
        if let duration = car.engineSoundDuration {
            return "\(duration.formatted(.number.precision(.fractionLength(1)))) s clip"
        }
        return "Recorded"
    }

    static func sharingSubtitle(_ car: Car) -> String {
        guard car.isPublic else { return "Private" }
        let groups = CarSharingSummary.sharedGroups(for: car)
        return groups.isEmpty ? "Public" : "Public · " + groups.joined(separator: ", ")
    }

    static func detailsSubtitle(_ car: Car) -> String {
        let parts = [car.trim, car.engine, car.transmission, car.color].filter { !$0.isEmpty }
        return parts.isEmpty ? "Add specs" : parts.prefix(3).joined(separator: " · ")
    }
}
