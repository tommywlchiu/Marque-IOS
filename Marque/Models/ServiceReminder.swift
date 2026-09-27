import Foundation

// A single upcoming service. Triggers can be date-based, mileage-based, or both.
// If both are set, whichever comes first determines status.
struct ServiceReminder: Identifiable, Codable, Equatable {
    var id: UUID
    var serviceType: String
    var notes: String
    var dueDate: Date?
    var dueMileage: Int?
    var isCompleted: Bool
    // Set when a reminder is completed (either via CarStore.completeReminder
    // or by logging a matching service). Optional so older Firestore docs
    // without this field decode with it as nil (including completed ones
    // logged before this field existed).
    var completedDate: Date?

    init(
        id: UUID = UUID(),
        serviceType: String = "",
        notes: String = "",
        dueDate: Date? = nil,
        dueMileage: Int? = nil,
        isCompleted: Bool = false,
        completedDate: Date? = nil
    ) {
        self.id = id
        self.serviceType = serviceType
        self.notes = notes
        self.dueDate = dueDate
        self.dueMileage = dueMileage
        self.isCompleted = isCompleted
        self.completedDate = completedDate
    }

    enum Status: String {
        case overdue, dueSoon, upcoming
    }

    func daysUntilDue(today: Date = Date()) -> Int? {
        guard let dueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: today, to: dueDate).day
    }

    func milesUntilDue(currentMileage: Int) -> Int? {
        guard let dueMileage else { return nil }
        return dueMileage - currentMileage
    }

    func status(currentMileage: Int, today: Date = Date()) -> Status {
        let days = daysUntilDue(today: today)
        let miles = milesUntilDue(currentMileage: currentMileage)

        if (days ?? Int.max) < 0 || (miles ?? Int.max) < 0 { return .overdue }
        if (days ?? Int.max) <= 7 || (miles ?? Int.max) <= 500 { return .dueSoon }
        return .upcoming
    }
}

// MARK: - Mock data for previews

extension ServiceReminder {
    static let preview: [ServiceReminder] = {
        let cal = Calendar.current
        return [
            ServiceReminder(
                serviceType: "Oil Change",
                notes: "Use 5W-30 synthetic",
                dueDate: cal.date(byAdding: .day, value: 5, to: Date()),
                dueMileage: 19_000
            ),
            ServiceReminder(
                serviceType: "Tire Rotation",
                dueDate: cal.date(byAdding: .day, value: 30, to: Date())
            ),
            ServiceReminder(
                serviceType: "Brake Inspection",
                dueMileage: 22_000
            ),
        ]
    }()
}
