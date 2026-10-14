import XCTest
@testable import Marque

final class GarageMissingInfoTests: XCTestCase {
    private func car(vin: String = "1HGCM82633A004352", mileage: String = "50,200",
                      bodyStyle: String = "Sedan", color: String = "Black") -> Car {
        Car(vinNumber: vin, color: color, mileage: mileage, bodyStyle: bodyStyle)
    }

    func testMissingFieldsProduceAttentionItemsWithADismissKey() {
        let c = car(vin: "", mileage: "", bodyStyle: "Sedan", color: "Black")
        let items = GarageSummary.attentionItems(for: c)
        let keys = Set(items.compactMap(\.dismissKey))
        XCTAssertEqual(keys, ["vin", "mileage"])
    }

    func testFilledFieldsProduceNoSuggestion() {
        let c = car()
        let keys = Set(GarageSummary.attentionItems(for: c).compactMap(\.dismissKey))
        XCTAssertTrue(keys.isEmpty)
    }

    func testDismissedFieldIsHiddenWhileStillBlank() {
        var c = car(vin: "")
        c.dismissedMissingInfo = ["vin"]
        let keys = Set(GarageSummary.attentionItems(for: c).compactMap(\.dismissKey))
        XCTAssertFalse(keys.contains("vin"))
    }

    func testPrunedDismissalsDropsAFilledField() {
        // Dismissed while blank, then the owner filled it in — the stale
        // dismissal must not survive the save, or a later re-blank would
        // stay silently suppressed forever instead of suggesting again.
        var c = car(vin: "1HGCM82633A004352")
        c.dismissedMissingInfo = ["vin", "mileage"]
        let pruned = GarageSummary.prunedDismissals(for: c)
        XCTAssertFalse(pruned.contains("vin"))
    }

    func testPrunedDismissalsKeepsAStillBlankField() {
        var c = car(vin: "")
        c.dismissedMissingInfo = ["vin"]
        XCTAssertEqual(GarageSummary.prunedDismissals(for: c), ["vin"])
    }

    func testOtherAttentionItemsAreNeverDismissible() throws {
        var c = car()
        c.registrationExpiryDate = Date().addingTimeInterval(-86_400) // expired yesterday
        let items = GarageSummary.attentionItems(for: c)
        let registrationItem = try XCTUnwrap(items.first { $0.target == .documents && $0.dismissKey == nil })
        XCTAssertNil(registrationItem.dismissKey)
    }
}

final class GarageStatusLineTests: XCTestCase {
    private let today = Date()

    func testExpiredRegistrationIsUrgent() {
        let car = Car(make: "BMW", model: "M4", year: "2016",
                      registrationExpiryDate: Calendar.current.date(byAdding: .day, value: -5, to: today))
        let line = GarageSummary.statusLine(for: car, today: today)
        XCTAssertEqual(line.text, "Registration expired")
        XCTAssertTrue(line.needsAttention)
        XCTAssertTrue(line.isUrgent)
    }

    func testExpiringSoonNeedsAttentionButIsNotUrgent() {
        let car = Car(make: "BMW", model: "M4", year: "2016",
                      insuranceExpiryDate: Calendar.current.date(byAdding: .day, value: 10, to: today))
        let line = GarageSummary.statusLine(for: car, today: today)
        XCTAssertTrue(line.needsAttention)
        XCTAssertFalse(line.isUrgent)
    }

    func testAllCaughtUpIsNeither() {
        let line = GarageSummary.statusLine(for: Car(make: "BMW", model: "M4", year: "2016"), today: today)
        XCTAssertEqual(line.text, "All caught up")
        XCTAssertFalse(line.needsAttention)
        XCTAssertFalse(line.isUrgent)
    }
}

final class CalendarDaysTests: XCTestCase {
    private let cal = Calendar.current

    private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testCountIsStableAcrossTheWholeDay() {
        // 10 calendar days away at 5pm: the old 24-hour-period math said 10
        // before 5pm and 9 after it.
        let due = date(23, hour: 17)
        XCTAssertEqual(cal.calendarDays(from: date(13, hour: 0, minute: 30), to: due), 10)
        XCTAssertEqual(cal.calendarDays(from: date(13, hour: 16, minute: 59), to: due), 10)
        XCTAssertEqual(cal.calendarDays(from: date(13, hour: 17, minute: 1), to: due), 10)
        XCTAssertEqual(cal.calendarDays(from: date(13, hour: 23, minute: 59), to: due), 10)
        XCTAssertEqual(cal.calendarDays(from: date(14, hour: 0, minute: 1), to: due), 9)
    }

    func testSameDayIsZeroAndPastDaysAreNegative() {
        XCTAssertEqual(cal.calendarDays(from: date(13, hour: 22), to: date(13, hour: 1)), 0)
        XCTAssertEqual(cal.calendarDays(from: date(13, hour: 1), to: date(12, hour: 23)), -1)
    }

    func testDocumentIsNotExpiredUntilItsDateHasPassed() {
        let today = Date()
        let startOfToday = cal.startOfDay(for: today)
        let expiresToday = Car(make: "BMW", model: "M4", year: "2016", insuranceExpiryDate: startOfToday)
        XCTAssertFalse(expiresToday.isInsuranceExpired)
        XCTAssertTrue(expiresToday.isInsuranceExpiringSoon)
        let expiredYesterday = Car(make: "BMW", model: "M4", year: "2016",
                                   insuranceExpiryDate: cal.date(byAdding: .day, value: -1, to: startOfToday))
        XCTAssertTrue(expiredYesterday.isInsuranceExpired)
        XCTAssertFalse(expiredYesterday.isInsuranceExpiringSoon)
    }

    func testReminderDueTodayIsDueTodayNotOverdue() {
        let r = ServiceReminder(serviceType: "Oil Change", dueDate: cal.startOfDay(for: date(13, hour: 12)))
        XCTAssertEqual(r.daysUntilDue(today: date(13, hour: 18)), 0)
        XCTAssertEqual(r.daysUntilDue(today: date(14, hour: 8)), -1)
    }
}

final class WidgetSelectionTests: XCTestCase {
    func testSelectedCarRoundTripsAndClears() throws {
        try XCTSkipIf(WidgetSharedStore.containerURL == nil, "no App Group container in this environment")
        let before = WidgetSharedStore.readSelectedCarID()
        defer { WidgetSharedStore.writeSelectedCarID(before) }
        let id = UUID().uuidString
        WidgetSharedStore.writeSelectedCarID(id)
        XCTAssertEqual(WidgetSharedStore.readSelectedCarID(), id)
        WidgetSharedStore.writeSelectedCarID(nil)
        XCTAssertNil(WidgetSharedStore.readSelectedCarID())
    }
}
