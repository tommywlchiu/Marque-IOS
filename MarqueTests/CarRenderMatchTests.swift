import XCTest
@testable import Marque

/// Which studio render a car gets. A wrong match shows someone a different
/// car (the "Silverado EV got the gas Silverado" bug).
final class CarRenderMatchTests: XCTestCase {
    private var catalog: CarRenderLibrary.Catalog!

    override func setUpWithError() throws {
        let credit = #"{"title":"t","author":"a","authorURL":"u","license":"CC BY","licenseURL":"l","url":"%@"}"#
        func entry(_ key: String, _ make: String, _ models: [String], _ years: [Int], extras: String = "null") -> String {
            let names = models.map { "\"\($0)\"" }.joined(separator: ",")
            return #"{"key":"\#(key)","make":"\#(make)","models":[\#(names)],"years":[\#(years[0]),\#(years[1])],"credit":\#(String(format: credit, key)),"plates":true,"tint":true,"wheels":["stock","five-blue"],"meter":0.5,"extras":\#(extras)}"#
        }
        let json = """
        {"version":1,"frames":36,"colors":["silver","green","red"],
         "cars":[\(entry("silverado-4g", "Chevrolet", ["Silverado", "Silverado 1500"], [2019, 2025])),
                 \(entry("silverado-ev", "Chevrolet", ["Silverado EV"], [2024, 2026])),
                 \(entry("model3", "Tesla", ["Model 3"], [2017, 2023], extras: #"{"rack":[0.1,-0.2,0.8,0.3]}"#))],
         "generics":[{"key":"generic-sedan","styles":["sedan"],"credit":\(String(format: credit, "gs"))},
                     {"key":"generic-suv","styles":["suv","crossover"],"credit":\(String(format: credit, "gv"))}]}
        """
        catalog = try JSONDecoder().decode(CarRenderLibrary.Catalog.self, from: Data(json.utf8))
    }

    private func match(_ make: String, _ model: String, _ year: String, style: String = "", color: String = "Silver") -> CarRenderLibrary.Match? {
        CarRenderLibrary.match(Car(make: make, model: model, year: year, color: color, bodyStyle: style), in: catalog)
    }

    func testMostSpecificModelNameWins() {
        XCTAssertEqual(match("Chevrolet", "Silverado EV", "2025")?.carKey, "silverado-ev")
        XCTAssertEqual(match("Chevrolet", "Silverado 1500", "2022")?.carKey, "silverado-4g")
    }

    func testTrailingWordsAfterTheModelStillMatch() {
        XCTAssertEqual(match("Tesla", "Model 3 Long Range", "2021")?.carKey, "model3")
    }

    func testMakeAndModelAreNormalized() {
        XCTAssertEqual(match("tesla", "model3", "2021")?.carKey, "model3")
    }

    func testOutOfRangeYearFallsBackToTheBodyStyleGeneric() {
        XCTAssertEqual(match("Tesla", "Model 3", "2025", style: "Sedan")?.carKey, "generic-sedan")
        XCTAssertEqual(match("Kia", "Telluride", "2024", style: "SUV")?.carKey, "generic-suv")
    }

    func testUnknownBodyStyleReadsAsASedan() {
        XCTAssertEqual(match("Kia", "Rio", "2015")?.carKey, "generic-sedan")
    }

    func testColorMapsToThePalette() {
        XCTAssertEqual(match("Tesla", "Model 3", "2021", color: "Forest Green")?.colorKey, "green")
        XCTAssertEqual(match("Tesla", "Model 3", "2021", color: "Midnight Cherry Red")?.colorKey, "red")
    }

    func testAddOnDataComesThrough() throws {
        let m = try XCTUnwrap(match("Tesla", "Model 3", "2021"))
        XCTAssertTrue(m.hasPlates && m.hasTint && m.canChangeStance)
        XCTAssertEqual(m.extras["rack"], CGRect(x: 0.1, y: -0.2, width: 0.8, height: 0.3))
        XCTAssertNil(match("Chevrolet", "Silverado", "2020")?.extras["rack"])
    }

    func testAnOlderCatalogWithoutAddOnsStillDecodes() throws {
        let json = #"{"version":1,"frames":36,"colors":["silver"],"cars":[]}"#
        XCTAssertNoThrow(try JSONDecoder().decode(CarRenderLibrary.Catalog.self, from: Data(json.utf8)))
    }
}
