import XCTest
@testable import Marque

final class RecallServiceTests: XCTestCase {
    /// NHTSA sends `null` (not just an absent key) for `parkIt`/`parkOutSide`
    /// on plenty of real campaigns. Declaring them as a plain (non-optional)
    /// `Bool` made `JSONDecoder` fail the *entire* results array the moment
    /// one entry hit this — a live, confirmed bug (2003 Honda Accord, 24 open
    /// recalls, several with null flags) that silently showed "no recalls"
    /// for a car with real, active safety recalls.
    func testNullParkFlagsDontFailTheWholeDecode() throws {
        let json = """
        {"Count":2,"Message":"ok","results":[
          {"NHTSACampaignNumber":"20V314000","Component":"FUEL SYSTEM:DELIVERY","Summary":"S1","Consequence":"C1","Remedy":"R1","ReportReceivedDate":"28/05/2020","parkIt":false,"parkOutSide":false},
          {"NHTSACampaignNumber":"19V182000","Component":"AIR BAGS:FRONTAL","Summary":"S2","Consequence":"C2","Remedy":"R2","ReportReceivedDate":"05/03/2019","parkIt":null,"parkOutSide":null}
        ]}
        """
        let recalls = try RecallService.decode(Data(json.utf8))
        XCTAssertEqual(recalls.count, 2)
        XCTAssertEqual(recalls[1].campaignNumber, "19V182000")
        XCTAssertEqual(recalls[1].parkIt, false)
        XCTAssertEqual(recalls[1].parkOutside, false)
    }

    func testMissingParkFlagKeysAlsoDefaultFalse() throws {
        let json = """
        {"Count":1,"Message":"ok","results":[
          {"NHTSACampaignNumber":"18V629000","Component":"BACK OVER PREVENTION:CAMERA","Summary":"S","Consequence":"C","Remedy":"R","ReportReceivedDate":"13/09/2018"}
        ]}
        """
        let recalls = try RecallService.decode(Data(json.utf8))
        XCTAssertEqual(recalls.count, 1)
        XCTAssertEqual(recalls[0].parkIt, false)
        XCTAssertEqual(recalls[0].parkOutside, false)
    }

    func testDisplayComponentIsTitleCasedAndDashJoined() {
        let recall = Recall(campaignNumber: "X", component: "AIR BAGS:FRONTAL:DRIVER SIDE:INFLATOR MODULE",
                             summary: "", consequence: "", remedy: "", reportDate: nil, parkIt: false, parkOutside: false)
        XCTAssertEqual(recall.displayComponent, "Air Bags – Frontal – Driver Side – Inflator Module")
    }
}
