import Foundation

// Suggests service reminders based on a car's maintenance history + industry-
// standard intervals. Pure functions — easy to test.
//
// Two consumers:
//   1. `suggest(for:)` — fallback source of suggestions when the AI Cloud
//      Function is unavailable. Filters out active reminders and returns
//      the soonest N.
//   2. `AddReminderView` — reads `interval(for:)`, `mileageAnchor(...)`, and
//      `dateAnchor(...)` to auto-configure trigger defaults when the user
//      picks a service type from the picker.
//
// Time-only vs mileage-only vs both:
// A service that degrades regardless of use (chemistry, rubber) gets a time
// trigger only. A service driven by wear gets a mileage trigger only. Safety-
// or engine-critical services get both, and `ServiceReminder.status()`
// triggers overdue when whichever comes first has elapsed.
enum ServiceReminderEngine {
    static let intervals: [String: (months: Int?, miles: Int?)] = [
        "Oil Change":            (months: 6,   miles: 5_000),
        "Tire Rotation":         (months: nil, miles: 7_500),
        "Tire Replacement":      (months: nil, miles: 50_000),
        "Brake Service":         (months: 24,  miles: 30_000),
        "Battery Replacement":   (months: 48,  miles: nil),   // chemistry ages regardless of use
        "Air Filter":            (months: 12,  miles: 15_000),
        "Transmission Service":  (months: 36,  miles: 60_000),
        "Coolant Flush":         (months: 36,  miles: nil),   // coolant chemistry ages
        "Spark Plugs":           (months: nil, miles: 60_000),
        "Alignment":             (months: nil, miles: 30_000),
        "Inspection":            (months: 12,  miles: nil),   // annual (state-dependent)
        "Wash / Detail":         (months: 3,   miles: nil),
    ]

    static func interval(for serviceType: String) -> (months: Int?, miles: Int?)? {
        intervals[serviceType]
    }

    // Anchor mileage for a service reminder's mileage trigger. Priority:
    //   1. Last service of this type with a recorded mileage
    //   2. Current mileage on the car
    //   3. nil — no mileage anchor available; caller should skip mileage trigger
    static func mileageAnchor(for serviceType: String, car: Car) -> Int? {
        let last = car.maintenanceRecords
            .filter { $0.serviceType == serviceType && !$0.mileage.isEmpty }
            .sorted { $0.date > $1.date }
            .first
        if let last {
            let m = mileage(from: last.mileage)
            if m > 0 { return m }
        }
        let current = mileage(from: car.mileage)
        return current > 0 ? current : nil
    }

    // Anchor date for a service reminder's date trigger — the most recent
    // service of this type, falling back to `today` when never serviced.
    static func dateAnchor(for serviceType: String, car: Car, today: Date = Date()) -> Date {
        car.maintenanceRecords
            .filter { $0.serviceType == serviceType }
            .map { $0.date }
            .max() ?? today
    }

    // Rounds a mileage value to the nearest 500 for readable next-service
    // targets ("55,500 mi" reads better than "51,247 mi"). 500 is well below
    // the safety margin on any of the intervals above.
    static func roundedMileage(_ value: Int) -> Int {
        ((value + 250) / 500) * 500
    }

    // Suggest reminders for service types that don't already have an active
    // reminder. Skips services whose triggers can't be computed (mileage-only
    // service with no mileage anchor). Capped at the same 3–6 range the AI
    // returns so the two suggestion sources feel comparable to the user.
    static func suggest(for car: Car, today: Date = Date()) -> [ServiceReminder] {
        let activeServiceTypes = Set(
            car.serviceReminders
                .filter { !$0.isCompleted }
                .map { $0.serviceType }
        )
        let cal = Calendar.current

        let all = intervals.compactMap { (type, interval) -> ServiceReminder? in
            if activeServiceTypes.contains(type) { return nil }

            let anchor = dateAnchor(for: type, car: car, today: today)
            let dueDate = interval.months.flatMap {
                cal.date(byAdding: .month, value: $0, to: anchor)
            }

            let dueMileage: Int? = {
                guard let miles = interval.miles,
                      let mileAnchor = mileageAnchor(for: type, car: car) else {
                    return nil
                }
                return roundedMileage(mileAnchor + miles)
            }()

            // Skip if neither trigger could be computed (e.g., mileage-only
            // service with no mileage anchor available).
            guard dueDate != nil || dueMileage != nil else { return nil }

            return ServiceReminder(
                serviceType: type,
                dueDate: dueDate,
                dueMileage: dueMileage
            )
        }
        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        return Array(all.prefix(6))
    }

    // Parses "42,500" -> 42500. Returns 0 for empty/invalid.
    static func mileage(from string: String) -> Int {
        let cleaned = string.replacingOccurrences(of: ",", with: "")
                            .trimmingCharacters(in: .whitespaces)
        return Int(cleaned) ?? 0
    }
}
