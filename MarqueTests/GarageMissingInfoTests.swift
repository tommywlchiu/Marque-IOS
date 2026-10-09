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
