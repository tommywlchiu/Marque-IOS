import UserNotifications

struct NotificationManager {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    static func scheduleExpiryNotifications(for cars: [Car]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for car in cars {
            if let regDate = car.registrationExpiryDate {
                scheduleAlert(
                    id: "reg-30-\(car.id)",
                    title: "Registration Expiring Soon",
                    body: "\(car.displayName) registration expires in 30 days.",
                    triggerDate: Calendar.current.date(byAdding: .day, value: -30, to: regDate)
                )
                scheduleAlert(
                    id: "reg-7-\(car.id)",
                    title: "Registration Expiring This Week",
                    body: "\(car.displayName) registration expires in 7 days.",
                    triggerDate: Calendar.current.date(byAdding: .day, value: -7, to: regDate)
                )
                scheduleAlert(
                    id: "reg-0-\(car.id)",
                    title: "Registration Expired",
                    body: "\(car.displayName) registration has expired. Renew it as soon as possible.",
                    triggerDate: regDate
                )
            }

            if let insDate = car.insuranceExpiryDate {
                scheduleAlert(
                    id: "ins-30-\(car.id)",
                    title: "Insurance Expiring Soon",
                    body: "\(car.displayName) insurance expires in 30 days.",
                    triggerDate: Calendar.current.date(byAdding: .day, value: -30, to: insDate)
                )
                scheduleAlert(
                    id: "ins-7-\(car.id)",
                    title: "Insurance Expiring This Week",
                    body: "\(car.displayName) insurance expires in 7 days.",
                    triggerDate: Calendar.current.date(byAdding: .day, value: -7, to: insDate)
                )
                scheduleAlert(
                    id: "ins-0-\(car.id)",
                    title: "Insurance Expired",
                    body: "\(car.displayName) insurance has expired. Renew it as soon as possible.",
                    triggerDate: insDate
                )
            }
        }
    }

    private static func scheduleAlert(id: String, title: String, body: String, triggerDate: Date?) {
        guard let triggerDate, triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
