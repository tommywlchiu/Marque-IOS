import XCTest
@testable import Marque

final class CarCustomizationTests: XCTestCase {
    private func decode(_ json: String) throws -> CarCustomization {
        try JSONDecoder().decode(CarCustomization.self, from: Data(json.utf8))
    }

    func testUnknownValuesFromANewerAppFallBackInsteadOfFailing() throws {
        let c = try decode(#"{"tint":"mirror","stance":"slammed","wheels":"x","extras":["snorkel","rack"],"seatColor":"plaid","spoilerFinish":"chrome","blackOptic":"maybe"}"#)
        XCTAssertEqual(c.tint, .none)
        XCTAssertEqual(c.stance, .stock)
        XCTAssertEqual(c.wheels, "x")
        XCTAssertEqual(c.extras, [.rack])
        XCTAssertEqual(c.seatColor, .standard)
        XCTAssertEqual(c.spoilerFinish, .gloss)
        XCTAssertEqual(c.blackOptic, false)
    }

    func testSeatColorAndSpoilerFinishRoundTrip() throws {
        var c = CarCustomization()
        c.seatColor = .white
        c.spoilerFinish = .carbon
        let decoded = try JSONDecoder().decode(CarCustomization.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded.seatColor, .white)
        XCTAssertEqual(decoded.spoilerFinish, .carbon)
    }

    func testDefaultSeatColorAndSpoilerFinishAreNotWritten() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CarCustomization())) as? [String: Any]
        XCTAssertNil(object?["seatColor"])
        XCTAssertNil(object?["spoilerFinish"])
    }

    func testBlackOpticRoundTrip() throws {
        var c = CarCustomization()
        c.blackOptic = true
        let decoded = try JSONDecoder().decode(CarCustomization.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded.blackOptic, true)
    }

    func testDefaultBlackOpticIsNotWritten() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CarCustomization())) as? [String: Any]
        XCTAssertNil(object?["blackOptic"])
    }

    func testEmptyObjectIsTheDefault() throws {
        XCTAssertEqual(try decode("{}"), CarCustomization())
    }

    func testCargoBoxAndCrossbarsReplaceEachOther() {
        var c = CarCustomization()
        c.setExtra(.rack, on: true)
        c.setExtra(.box, on: true)
        XCTAssertEqual(c.extras, [.box])
        c.setExtra(.rack, on: true)
        XCTAssertEqual(c.extras, [.rack])
    }

    func testStoredBoxAndRackNormalizeToTheBox() throws {
        XCTAssertEqual(try decode(#"{"extras":["rack","box","box"]}"#).extras, [.box])
    }

    func testExtrasAreKeptInDrawingOrder() {
        var c = CarCustomization()
        c.setExtra(.lightbar, on: true)
        c.setExtra(.spoiler, on: true)
        c.setExtra(.box, on: true)
        XCTAssertEqual(c.extras, [.spoiler, .box, .lightbar])
        c.setExtra(.box, on: false)
        XCTAssertEqual(c.extras, [.spoiler, .lightbar])
    }

    func testNoExtrasAreNotWritten() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CarCustomization())) as? [String: Any]
        XCTAssertNil(object?["extras"])
    }

    /// Builds before the black-is-standard change stored `black` for the seat
    /// overlay; it must decode to `.standard`, the same look.
    func testLegacyBlackSeatColorDecodesAsStandard() throws {
        XCTAssertEqual(try decode(#"{"seatColor":"black"}"#).seatColor, .standard)
    }
}

/// The owner's render build is published on `PublicCar.customization`, gated
/// with the "specs" sharing group. A stock car publishes nothing.
final class PublicCarBuildTests: XCTestCase {
    private func car(build: CarCustomization, specs: Bool) -> Car {
        var car = Car()
        car.make = "Porsche"; car.model = "911"; car.year = "2021"; car.color = "Silver"
        car.customization = build
        var sharing = PublicSharingSettings.legacyAllOn
        sharing.specs = specs
        car.publicSharing = sharing
        return car
    }

    private func project(_ car: Car) -> PublicCar {
        PublicCar(from: car, ownerUID: "u", ownerUsername: "u", ownerAvatarURL: nil)
    }

    func testStockCarPublishesNoBuild() {
        XCTAssertNil(project(car(build: CarCustomization(), specs: true)).customization)
    }

    func testModifiedCarPublishesItsBuild() {
        let build = CarCustomization(tint: .medium, stance: .lowered, wheels: "multi-gold", extras: [.spoiler], blackOptic: true)
        XCTAssertEqual(project(car(build: build, specs: true)).customization, build)
    }

    func testSpecsGroupOffHidesTheBuild() {
        let build = CarCustomization(tint: .limo, stance: .lifted)
        XCTAssertNil(project(car(build: build, specs: false)).customization)
    }

    func testBuildSurvivesTheWireEncoding() throws {
        let build = CarCustomization(tint: .light, stance: .lowered, wheels: "twin-green")
        let sent = project(car(build: build, specs: true))
        let received = try JSONDecoder().decode(PublicCar.self, from: JSONEncoder().encode(sent))
        XCTAssertEqual(received.customization, build)
    }

    func testOldDocumentsWithoutABuildDecodeAsNil() throws {
        let json = #"{"carId":"c","ownerUID":"u","make":"Honda","model":"Civic","year":"2020"}"#
        XCTAssertNil(try JSONDecoder().decode(PublicCar.self, from: Data(json.utf8)).customization)
    }

    func testPlateAndOtherPrivateFieldsAreNeverInTheBuild() throws {
        var c = car(build: CarCustomization(tint: .medium), specs: true)
        c.licensePlate = "SECRET1"
        let data = try JSONEncoder().encode(project(c))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SECRET1"))
    }
}
