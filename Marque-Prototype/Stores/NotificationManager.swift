import UserNotifications

struct NotificationManager {
    static let insuranceAlertsKey = "marque_notif_insurance_enabled"
    static let registrationAlertsKey = "marque_notif_registration_enabled"
    static let maintenanceRemindersKey = "marque_notif_maintenance_enabled"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // Full reschedule — cancels all pending Marque notifications then rebuilds
    // from the current cars array (and optional driver-license expiry).
    // Call this on app launch and whenever carStore.cars or the user's license
    // expiry changes.
    static func scheduleAll(for cars: [Car], licenseExpiry: Date? = nil) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for car in cars {
            scheduleExpiryAlerts(for: car)
            scheduleReminderAlerts(for: car)
        }
        if let licenseExpiry {
            scheduleLicenseExpiryAlerts(expiry: licenseExpiry)
        }
    }

    // MARK: - Driver license expiry alerts

    private static func scheduleLicenseExpiryAlerts(expiry: Date) {
        scheduleAlert(
            id: "dl-30",
            carId: nil,
            title: "Driver License Expiring Soon",
            body: "Your driver's license expires in 30 days.",
            triggerDate: Calendar.current.date(byAdding: .day, value: -30, to: expiry)
        )
        scheduleAlert(
            id: "dl-7",
            carId: nil,
            title: "Driver License Expiring This Week",
            body: "Your driver's license expires in 7 days.",
            triggerDate: Calendar.current.date(byAdding: .day, value: -7, to: expiry)
        )
        scheduleAlert(
            id: "dl-0",
            carId: nil,
            title: "Driver License Expired",
            body: "Your driver's license has expired. Renew it as soon as possible.",
            triggerDate: expiry
        )
    }

    // MARK: - Expiry alerts (registration & insurance)

    private static func scheduleExpiryAlerts(for car: Car) {
        if UserDefaults.standard.object(forKey: registrationAlertsKey) == nil
            || UserDefaults.standard.bool(forKey: registrationAlertsKey),
           let regDate = car.registrationExpiryDate {
            scheduleAlert(
                id: "reg-30-\(car.id)",
                carId: car.id,
                title: "Registration Expiring Soon",
                body: "\(car.displayName) registration expires in 30 days.",
                triggerDate: Calendar.current.date(byAdding: .day, value: -30, to: regDate)
            )
            scheduleAlert(
                id: "reg-7-\(car.id)",
                carId: car.id,
                title: "Registration Expiring This Week",
                body: "\(car.displayName) registration expires in 7 days.",
                triggerDate: Calendar.current.date(byAdding: .day, value: -7, to: regDate)
            )
            scheduleAlert(
                id: "reg-0-\(car.id)",
                carId: car.id,
                title: "Registration Expired",
                body: "\(car.displayName) registration has expired. Renew it as soon as possible.",
                triggerDate: regDate
            )
        }

        if UserDefaults.standard.object(forKey: insuranceAlertsKey) == nil
            || UserDefaults.standard.bool(forKey: insuranceAlertsKey),
           let insDate = car.insuranceExpiryDate {
            scheduleAlert(
                id: "ins-30-\(car.id)",
                carId: car.id,
                title: "Insurance Expiring Soon",
                body: "\(car.displayName) insurance expires in 30 days.",
                triggerDate: Calendar.current.date(byAdding: .day, value: -30, to: insDate)
            )
            scheduleAlert(
                id: "ins-7-\(car.id)",
                carId: car.id,
                title: "Insurance Expiring This Week",
                body: "\(car.displayName) insurance expires in 7 days.",
                triggerDate: Calendar.current.date(byAdding: .day, value: -7, to: insDate)
            )
            scheduleAlert(
                id: "ins-0-\(car.id)",
                carId: car.id,
                title: "Insurance Expired",
                body: "\(car.displayName) insurance has expired. Renew it as soon as possible.",
                triggerDate: insDate
            )
        }
    }

    // MARK: - Service reminder alerts

    private static func scheduleReminderAlerts(for car: Car) {
        guard UserDefaults.standard.bool(forKey: maintenanceRemindersKey) else { return }

        let cID = car.id.uuidString
        let carName = car.displayName

        for reminder in car.serviceReminders where !reminder.isCompleted {
            guard let dueDate = reminder.dueDate else { continue }

            let type = reminder.serviceType
            let rID = reminder.id.uuidString

            scheduleAlert(
                id: "svc-7-\(cID)-\(rID)",
                carId: car.id,
                title: "\(type) Due Soon",
                body: "\(carName) is due for \(type.lowercased()) in 7 days.",
                triggerDate: Calendar.current.date(byAdding: .day, value: -7, to: dueDate)
            )
            scheduleAlert(
                id: "svc-0-\(cID)-\(rID)",
                carId: car.id,
                title: "\(type) Due Today",
                body: "\(carName) is due for \(type.lowercased()) today.",
                triggerDate: dueDate
            )
        }
    }

    // MARK: - Shared

    private static func scheduleAlert(id: String, carId: UUID?, title: String, body: String, triggerDate: Date?) {
        guard let triggerDate, triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let carId {
            content.userInfo = ["carId": carId.uuidString]
        }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
