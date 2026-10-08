import XCTest
@testable import Marque

/// `Car` is persisted locally and in Firestore, so a decoding change can
/// silently drop or reset every user's data. These pin the migrations.
final class CarCodingTests: XCTestCase {
    private func json(of car: Car) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(car)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> Car {
        try JSONDecoder().decode(Car.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testRoundTripKeepsNewerFields() throws {
        var car = Car(make: "Ford", model: "F-150", year: "2020", fuelType: "Diesel",
                      fullRange: 650, fullRangeIsEstimate: true, tankGallons: 26)
        car.customization.setExtra(.lightbar, on: true)
        let back = try JSONDecoder().decode(Car.self, from: JSONEncoder().encode(car))
        XCTAssertEqual(back.fullRange, 650)
        XCTAssertTrue(back.fullRangeIsEstimate)
        XCTAssertEqual(back.tankGallons, 26)
        XCTAssertEqual(back.customization.extras, [.lightbar])
    }

    func testLegacySinglePhotoKeyMigrates() throws {
        var object = try json(of: Car(make: "Honda", model: "Accord", year: "2007"))
        object["photoFileNames"] = nil
        object["photoFileName"] = "cover.jpg"
        XCTAssertEqual(try decode(object).photoFileNames, ["cover.jpg"])
    }

    func testMissingSharingSettingsKeepsAPublicCarFullyShared() throws {
        var object = try json(of: Car(make: "BMW", model: "M4", year: "2018", isPublic: true))
        object["publicSharing"] = nil
        XCTAssertEqual(try decode(object).publicSharing, .legacyAllOn)
    }

    func testMissingSharingSettingsGivesAPrivateCarPrivacyFirstDefaults() throws {
        var object = try json(of: Car(make: "BMW", model: "M4", year: "2018", isPublic: false))
        object["publicSharing"] = nil
        XCTAssertEqual(try decode(object).publicSharing, .privacyFirst)
    }

    func testFieldsAddedLaterAreOptional() throws {
        var object = try json(of: Car(make: "Toyota", model: "Camry", year: "2019"))
        for key in ["fullRange", "fullRangeIsEstimate", "tankGallons", "customization", "trim", "bodyStyle"] {
            object[key] = nil
        }
        let car = try decode(object)
        XCTAssertNil(car.fullRange)
        XCTAssertEqual(car.customization, CarCustomization())
    }

    func testABadNewerFieldDoesNotFailTheWholeCar() throws {
        var object = try json(of: Car(make: "Tesla", model: "Model 3", year: "2021"))
        object["fullRange"] = "not a number"
        XCTAssertNil(try decode(object).fullRange)
    }
}

final class CarRangeTests: XCTestCase {
    func testRangeKindByFuelType() {
        XCTAssertEqual(Car(fuelType: "Electric").rangeKind, .charge)
        XCTAssertEqual(Car(fuelType: "Hybrid").rangeKind, .tank)
        XCTAssertEqual(Car(fuelType: "Plug-in Hybrid").rangeKind, .tank)
        XCTAssertEqual(Car(fuelType: "Diesel").rangeKind, .tank)
        XCTAssertNil(Car(fuelType: "Gasoline").rangeKind)
    }

    func testTankSizeIsTrackedForDieselAndPlainHybridsOnly() {
        XCTAssertTrue(Car.tracksTankSize(fuelType: "Diesel"))
        XCTAssertTrue(Car.tracksTankSize(fuelType: "Hybrid"))
        XCTAssertFalse(Car.tracksTankSize(fuelType: "Plug-in Hybrid"))
        XCTAssertFalse(Car.tracksTankSize(fuelType: "Electric"))
    }

    func testRangeTextNeedsAPositiveRangeAndARangeFuel() {
        XCTAssertEqual(Car(fuelType: "Electric", fullRange: 358).rangeText, "358 mi")
        XCTAssertNil(Car(fuelType: "Electric", fullRange: 0).rangeText)
        XCTAssertNil(Car(fuelType: "Gasoline", fullRange: 400).rangeText)
    }
}
