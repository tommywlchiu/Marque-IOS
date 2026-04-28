import Foundation

// Suggests service reminders based on a car's maintenance history and
// industry-standard service intervals. Pure functions — easy to test.
enum ServiceReminderEngine {
    // Industry-standard intervals (months / miles). Tweak per region.
    private static let intervals: [String: (months: Int?, miles: Int?)] = [
        "Oil Change":         (months: 6,  miles: 5_000),
        "Tire Rotation":      (months: 6,  miles: 7_500),
        "Air Filter":         (months: 12, miles: 15_000),
        "Brake Service":      (months: 24, miles: 30_000),
        "Transmission Service":(months: 36, miles: 60_000),
        "Coolant Flush":      (months: 36, miles: 30_000),
    ]

    // Suggest reminders for service types that don't already have an active reminder.
    static func suggest(for car: Car, today: Date = Date()) -> [ServiceReminder] {
        let activeServiceTypes = Set(
            car.serviceReminders
                .filter { !$0.isCompleted }
                .map { $0.serviceType }
        )
        let currentMileage = mileage(from: car.mileage)
        let cal = Calendar.current

        return intervals.compactMap { (type, interval) -> ServiceReminder? in
            // Skip if user already has an active reminder for this type.
            if activeServiceTypes.contains(type) { return nil }

            // Anchor to most recent service of this type, or today if never serviced.
            let lastService = car.maintenanceRecords
                .filter { $0.serviceType == type }
                .map { $0.date }
                .max()

            let anchor = lastService ?? today
            let lastMileage = lastServiceMileage(car: car, type: type) ?? currentMileage

            let dueDate = interval.months.flatMap {
                cal.date(byAdding: .month, value: $0, to: anchor)
            }
            let dueMileage = interval.miles.map { lastMileage + $0 }

            return ServiceReminder(
                serviceType: type,
                dueDate: dueDate,
                dueMileage: dueMileage
            )
        }
        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    // Parse "42,500" -> 42500. Returns 0 for empty/invalid.
    static func mileage(from string: String) -> Int {
        let cleaned = string.replacingOccurrences(of: ",", with: "")
                            .trimmingCharacters(in: .whitespaces)
        return Int(cleaned) ?? 0
    }

    private static func lastServiceMileage(car: Car, type: String) -> Int? {
        car.maintenanceRecords
            .filter { $0.serviceType == type }
            .sorted { $0.date > $1.date }
            .first
            .map { mileage(from: $0.mileage) }
    }
}
