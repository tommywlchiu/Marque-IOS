import XCTest
@testable import Marque

final class CarCustomizationTests: XCTestCase {
    private func decode(_ json: String) throws -> CarCustomization {
        try JSONDecoder().decode(CarCustomization.self, from: Data(json.utf8))
    }

    func testUnknownValuesFromANewerAppFallBackInsteadOfFailing() throws {
        let c = try decode(#"{"tint":"mirror","stance":"slammed","wheels":"x","extras":["snorkel","rack"],"seatColor":"plaid","spoilerFinish":"chrome","lightingMode":"dusk","blackOptic":"maybe"}"#)
        XCTAssertEqual(c.tint, .none)
        XCTAssertEqual(c.stance, .stock)
        XCTAssertEqual(c.wheels, "x")
        XCTAssertEqual(c.extras, [.rack])
        XCTAssertEqual(c.seatColor, .standard)
        XCTAssertEqual(c.spoilerFinish, .gloss)
        XCTAssertEqual(c.lightingMode, .day)
        XCTAssertEqual(c.blackOptic, false)
    }

    func testLightingModeRoundTrip() throws {
        var c = CarCustomization()
        c.lightingMode = .night
        let decoded = try JSONDecoder().decode(CarCustomization.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded.lightingMode, .night)
    }

    func testDefaultLightingModeIsNotWritten() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CarCustomization())) as? [String: Any]
        XCTAssertNil(object?["lightingMode"])
    }

    func testSeatColorAndSpoilerFinishRoundTrip() throws {
        var c = CarCustomization()
        c.seatColor = .black
        c.spoilerFinish = .carbon
        let decoded = try JSONDecoder().decode(CarCustomization.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded.seatColor, .black)
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
}
