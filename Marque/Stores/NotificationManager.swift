import UserNotifications

struct NotificationManager {
    static let insuranceAlertsKey = "marque_notif_insurance_enabled"
    static let registrationAlertsKey = "marque_notif_registration_enabled"
    static let warrantyAlertsKey = "marque_notif_warranty_enabled"
    static let maintenanceRemindersKey = "marque_notif_maintenance_enabled"

    static func requestPermission() {
        let center = UNUserNotificationCenter.current()
        // FR-11.4 `notification_permission_result` measures the opt-in rate, so it
        // has to correspond 1:1 with a prompt the user actually answered. Only the
        // first call prompts; every later one (app launch, and each of the four
        // alert toggles) returns the stored decision immediately without showing
        // anything. Reporting unconditionally would therefore emit one event per
        // launch and per toggle tap and make the rate meaningless, so the status is
        // read first and the event is gated on `.notDetermined`.
        center.getNotificationSettings { settings in
            let isFirstPrompt = settings.authorizationStatus == .notDetermined
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                guard isFirstPrompt else { return }
                AnalyticsService.notificationPermissionResult(granted: granted)
            }
        }
    }

    // Full reschedule — cancels all pending Marque notifications then rebuilds
    // from the current cars array (and optional driver-license expiry).
    // Call this on app launch and whenever carStore.cars or the user's license
    // expiry changes.
    static func scheduleAll(for cars: [Car], licenseExpiry: Date? = nil) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        var alerts: [PendingAlert] = []
        for car in cars {
            alerts += expiryAlerts(for: car)
            alerts += reminderAlerts(for: car)
            alerts += mileageCheckInAlerts(for: car)
        }
        if let licenseExpiry {
            alerts += licenseExpiryAlerts(expiry: licenseExpiry)
        }

        // iOS keeps at most 64 pending local notifications per app and silently
        // drops the rest. Schedule soonest-first so anything cut is the furthest
        // out; it gets picked up by a later reschedule once nearer alerts fire.
        let upcoming = alerts
            .filter { $0.fireDate > Date() }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maxPendingAlerts)
        for alert in upcoming {
            center.add(alert.request)
        }
    }

    private static let maxPendingAlerts = 64

    /// Alerts fire at this local hour on their day. Stored dates are midnight,
    /// so using their own time would fire at 12 AM, and would skip a same-day
    /// alert entirely because midnight had already passed when it was set.
    private static let alertHour = 9

    // MARK: - Driver license expiry alerts

    private static func licenseExpiryAlerts(expiry: Date) -> [PendingAlert] {
        [
            alert(
                id: "dl-30",
                carId: nil,
                title: "Driver License Expiring Soon",
                body: "Your driver's license expires in 30 days.",
                day: Calendar.current.date(byAdding: .day, value: -30, to: expiry)
            ),
            alert(
                id: "dl-7",
                carId: nil,
                title: "Driver License Expiring This Week",
                body: "Your driver's license expires in 7 days.",
                day: Calendar.current.date(byAdding: .day, value: -7, to: expiry)
            ),
            alert(
                id: "dl-0",
                carId: nil,
                title: "Driver License Expired",
                body: "Your driver's license has expired. Renew it as soon as possible.",
                day: expiry
            ),
        ].compactMap { $0 }
    }

    // MARK: - Expiry alerts (registration, insurance & warranty)

    private static func expiryAlerts(for car: Car) -> [PendingAlert] {
        var alerts: [PendingAlert?] = []

        if UserDefaults.standard.object(forKey: registrationAlertsKey) == nil
            || UserDefaults.standard.bool(forKey: registrationAlertsKey),
           let regDate = car.registrationExpiryDate {
            alerts += [
                alert(
                    id: "reg-30-\(car.id)",
                    carId: car.id,
                    title: "Registration Expiring Soon",
                    body: "\(car.displayName) registration expires in 30 days.",
                    day: Calendar.current.date(byAdding: .day, value: -30, to: regDate)
                ),
                alert(
                    id: "reg-7-\(car.id)",
                    carId: car.id,
                    title: "Registration Expiring This Week",
                    body: "\(car.displayName) registration expires in 7 days.",
                    day: Calendar.current.date(byAdding: .day, value: -7, to: regDate)
                ),
                alert(
                    id: "reg-0-\(car.id)",
                    carId: car.id,
                    title: "Registration Expired",
                    body: "\(car.displayName) registration has expired. Renew it as soon as possible.",
                    day: regDate
                ),
            ]
        }

        if UserDefaults.standard.object(forKey: insuranceAlertsKey) == nil
            || UserDefaults.standard.bool(forKey: insuranceAlertsKey),
           let insDate = car.insuranceExpiryDate {
            alerts += [
                alert(
                    id: "ins-30-\(car.id)",
                    carId: car.id,
                    title: "Insurance Expiring Soon",
                    body: "\(car.displayName) insurance expires in 30 days.",
                    day: Calendar.current.date(byAdding: .day, value: -30, to: insDate)
                ),
                alert(
                    id: "ins-7-\(car.id)",
                    carId: car.id,
                    title: "Insurance Expiring This Week",
                    body: "\(car.displayName) insurance expires in 7 days.",
                    day: Calendar.current.date(byAdding: .day, value: -7, to: insDate)
                ),
                alert(
                    id: "ins-0-\(car.id)",
                    carId: car.id,
                    title: "Insurance Expired",
                    body: "\(car.displayName) insurance has expired. Renew it as soon as possible.",
                    day: insDate
                ),
            ]
        }

        if UserDefaults.standard.object(forKey: warrantyAlertsKey) == nil
            || UserDefaults.standard.bool(forKey: warrantyAlertsKey),
           let warrantyDate = car.warrantyExpiryDate {
            alerts += [
                alert(
                    id: "warranty-30-\(car.id)",
                    carId: car.id,
                    title: "Warranty Expiring Soon",
                    body: "\(car.displayName) warranty expires in 30 days.",
                    day: Calendar.current.date(byAdding: .day, value: -30, to: warrantyDate)
                ),
                alert(
                    id: "warranty-7-\(car.id)",
                    carId: car.id,
                    title: "Warranty Expiring This Week",
                    body: "\(car.displayName) warranty expires in 7 days.",
                    day: Calendar.current.date(byAdding: .day, value: -7, to: warrantyDate)
                ),
                alert(
                    id: "warranty-0-\(car.id)",
                    carId: car.id,
                    title: "Warranty Expired",
                    body: "\(car.displayName) warranty has expired.",
                    day: warrantyDate
                ),
            ]
        }

        return alerts.compactMap { $0 }
    }

    // MARK: - Service reminder alerts

    private static func reminderAlerts(for car: Car) -> [PendingAlert] {
        // On by default, matching the insurance/registration pattern: absent
        // key (never toggled) reads as enabled, not disabled.
        guard UserDefaults.standard.object(forKey: maintenanceRemindersKey) == nil
            || UserDefaults.standard.bool(forKey: maintenanceRemindersKey) else { return [] }

        let cID = car.id.uuidString
        let carName = car.displayName
        var alerts: [PendingAlert?] = []

        for reminder in car.serviceReminders where !reminder.isCompleted {
            guard let dueDate = reminder.dueDate else { continue }

            let type = reminder.serviceType
            let rID = reminder.id.uuidString

            alerts += [
                alert(
                    id: "svc-7-\(cID)-\(rID)",
                    carId: car.id,
                    title: "\(type) Due Soon",
                    body: "\(carName) is due for \(type.lowercased()) in 7 days.",
                    day: Calendar.current.date(byAdding: .day, value: -7, to: dueDate)
                ),
                alert(
                    id: "svc-0-\(cID)-\(rID)",
                    carId: car.id,
                    title: "\(type) Due Today",
                    body: "\(carName) is due for \(type.lowercased()) today.",
                    day: dueDate
                ),
            ]
        }

        return alerts.compactMap { $0 }
    }

    // MARK: - Mileage check-in alert

    // Mileage-only reminders can never fire a date-based local notification on
    // their own, so instead nudge the user to update their mileage so those
    // reminders stay accurate. One alert per car with an open mileage
    // reminder, gated on the same toggle as the other service alerts. Fires
    // on the next 30-day mark after the last known mileage update. The anchor
    // must be a stored date, never "now": scheduleAll runs on every launch
    // and car change, so a now-relative date would slide forward forever (or,
    // once overdue, re-fire every day). With no known anchor there's no alert;
    // the in-app check-in card covers that case.
    private static let mileageCheckInDays = 30

    private static func mileageCheckInAlerts(for car: Car) -> [PendingAlert] {
        guard UserDefaults.standard.object(forKey: maintenanceRemindersKey) == nil
            || UserDefaults.standard.bool(forKey: maintenanceRemindersKey),
            car.hasOpenMileageReminders else { return [] }

        let lastRecordWithMileage = car.maintenanceRecords
            .filter { $0.mileageValue != nil }
            .map(\.date)
            .max()
        guard let anchor = car.mileageUpdatedAt ?? lastRecordWithMileage else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let daysSince = max(0, calendar.dateComponents([.day], from: anchor, to: now).day ?? 0)
        let periods = daysSince / mileageCheckInDays + 1
        guard let day = calendar.date(byAdding: .day, value: periods * mileageCheckInDays, to: anchor) else { return [] }

        return [
            alert(
                id: "mileage-checkin-\(car.id)",
                carId: car.id,
                title: "How many miles on your \(car.displayName)?",
                body: "Update your mileage so service reminders stay accurate.",
                day: day
            )
        ].compactMap { $0 }
    }

    // MARK: - Shared

    private struct PendingAlert {
        let fireDate: Date
        let request: UNNotificationRequest
    }

    /// Builds an alert that fires at `alertHour` local time on `day`'s calendar
    /// day. Returns nil if `day` is nil or the fire time can't be computed;
    /// past fire times are filtered in `scheduleAll`.
    private static func alert(id: String, carId: UUID?, title: String, body: String, day: Date?) -> PendingAlert? {
        guard let day else { return nil }
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = alertHour
        components.minute = 0
        guard let fireDate = calendar.date(from: components) else { return nil }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let carId {
            content.userInfo = ["carId": carId.uuidString]
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return PendingAlert(
            fireDate: fireDate,
            request: UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }
}
