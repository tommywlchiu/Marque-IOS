import XCTest
@testable import Marque

/// A scanned "2026-03-15" must stay March 15 in the user's own time zone
/// (it once showed — and reminded — a day early for every US user).
final class DateAnchorTests: XCTestCase {
    private var savedZone: TimeZone!

    override func setUp() { savedZone = NSTimeZone.default }
    override func tearDown() { NSTimeZone.default = savedZone }

    func testScannedDateKeepsItsCalendarDayInEveryTimeZone() throws {
        for id in ["America/Los_Angeles", "America/New_York", "UTC", "Asia/Tokyo", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: id))
            let date = try XCTUnwrap(DocumentScanService.parseISODate("2026-03-15"), id)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = NSTimeZone.default
            let day = calendar.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual([day.year, day.month, day.day], [2026, 3, 15], id)
        }
    }

    func testRejectsEmptyAndMalformed() {
        XCTAssertNil(DocumentScanService.parseISODate(""))
        XCTAssertNil(DocumentScanService.parseISODate("03/15/2026"))
    }
}

final class NumberParsingTests: XCTestCase {
    func testMileageKeepsDigitsOnly() {
        XCTAssertEqual(NumberParsing.mileage(from: "25,000 mi"), 25_000)
        XCTAssertNil(NumberParsing.mileage(from: "mi"))
        XCTAssertNil(NumberParsing.mileage(from: ""))
    }

    func testCostKeepsOneDecimalPoint() {
        XCTAssertEqual(NumberParsing.cost(from: "$1,234.50"), 1234.5)
        XCTAssertNil(NumberParsing.cost(from: ""))
    }
}
