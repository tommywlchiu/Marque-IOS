import XCTest
@testable import Marque

final class RecallTriageTests: XCTestCase {
    private func recall(_ n: String, parkIt: Bool = false, ota: Bool = false) -> Recall {
        Recall(campaignNumber: n, component: "AIR BAGS:FRONTAL", summary: "", consequence: "", remedy: "",
               reportDate: nil, parkIt: parkIt, parkOutside: false, overTheAir: ota)
    }

    func testOverTheAirFlagDecodes() throws {
        let json = """
        {"Count":2,"Message":"ok","results":[
          {"NHTSACampaignNumber":"22V001000","Component":"C","Summary":"S","Consequence":"C","Remedy":"R","ReportReceivedDate":"01/01/2022","overTheAirUpdate":true},
          {"NHTSACampaignNumber":"22V002000","Component":"C","Summary":"S","Consequence":"C","Remedy":"R","ReportReceivedDate":"01/01/2022","overTheAirUpdate":null}
        ]}
        """
        let recalls = try RecallService.decode(Data(json.utf8))
        XCTAssertTrue(recalls[0].overTheAir)
        XCTAssertFalse(recalls[1].overTheAir)
    }

    func testTriageGroupsEveryRecallExactlyOnce() {
        let all = [recall("A"), recall("B", ota: true), recall("C", parkIt: true), recall("D"), recall("E", ota: true)]
        let t = RecallTriage(recalls: all, resolved: ["D"])
        XCTAssertEqual(t.doNotDrive.map(\.campaignNumber), ["C"])
        XCTAssertEqual(t.toCheck.map(\.campaignNumber), ["A"])
        XCTAssertEqual(t.likelyFixed.map(\.campaignNumber), ["B", "E"])
        XCTAssertEqual(t.resolved.map(\.campaignNumber), ["D"])
    }

    func testOwnerMarkWinsOverEveryOtherGroupIncludingDoNotDrive() {
        let t = RecallTriage(recalls: [recall("C", parkIt: true)], resolved: ["C"])
        XCTAssertTrue(t.doNotDrive.isEmpty)
        XCTAssertEqual(t.resolved.map(\.campaignNumber), ["C"])
    }

    func testAttentionCardFoldsManyRecallsIntoOneRow() {
        let car = Car(make: "Tesla", model: "Model 3", year: "2022")
        let recalls = (1...18).map { recall("R\($0)") } + [recall("OTA", ota: true)]
        let items = GarageSummary.attentionItems(for: car, recalls: recalls)
        let rows = items.filter { $0.id.hasPrefix("recall") }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "18 recalls issued for your 2022 Tesla Model 3")
        XCTAssertFalse(rows[0].subtitle.localizedCaseInsensitiveContains("available"))
    }

    func testDoNotDriveKeepsItsOwnUrgentRow() {
        let car = Car(make: "Tesla", model: "Model 3", year: "2022")
        let items = GarageSummary.attentionItems(for: car, recalls: [recall("C", parkIt: true), recall("A")])
        XCTAssertEqual(items.filter { $0.id.hasPrefix("recall") }.map(\.id), ["recall-C", "recalls-to-check"])
        XCTAssertTrue(items[0].isUrgent)
    }

    func testOverTheAirOnlyAndResolvedRecallsLeaveTheCardEmpty() {
        var car = Car(make: "Tesla", model: "Model 3", year: "2022")
        car.resolvedRecalls = ["A"]
        let items = GarageSummary.attentionItems(for: car, recalls: [recall("A"), recall("B", ota: true)])
        XCTAssertTrue(items.filter { $0.id.hasPrefix("recall") }.isEmpty)
    }

    func testResolvedRecallsRoundTripAndAreOmittedWhenEmpty() throws {
        var car = Car(make: "Tesla", model: "Model 3", year: "2022")
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(car)) as? [String: Any]
        XCTAssertNil(empty?["resolvedRecalls"])
        car.resolvedRecalls = ["22V001000"]
        let decoded = try JSONDecoder().decode(Car.self, from: JSONEncoder().encode(car))
        XCTAssertEqual(decoded.resolvedRecalls, ["22V001000"])
    }
}
