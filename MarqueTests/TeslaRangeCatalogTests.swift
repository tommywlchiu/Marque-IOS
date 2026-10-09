import XCTest
@testable import Marque

final class TeslaRangeCatalogTests: XCTestCase {
    func testModel3AndModelYHaveVariantsAcrossTheCatalogsYears() {
        for year in 2017...2024 {
            XCTAssertNotNil(TeslaRangeCatalog.variants(model: "Model 3", year: "\(year)"), "Model 3 \(year)")
        }
        for year in 2020...2024 {
            XCTAssertNotNil(TeslaRangeCatalog.variants(model: "Model Y", year: "\(year)"), "Model Y \(year)")
        }
    }

    func testUnknownModelOrYearReturnsNil() {
        XCTAssertNil(TeslaRangeCatalog.variants(model: "Model S", year: "2022"))
        XCTAssertNil(TeslaRangeCatalog.variants(model: "Model 3", year: "2015"))
        XCTAssertNil(TeslaRangeCatalog.variants(model: "Accord", year: "2022"))
    }

    func testEveryVariantHasAPlausibleRange() {
        for year in 2017...2024 {
            for v in TeslaRangeCatalog.variants(model: "Model 3", year: "\(year)") ?? [] {
                XCTAssertGreaterThan(v.miles, 150, "\(year) \(v.name)")
                XCTAssertLessThan(v.miles, 450, "\(year) \(v.name)")
            }
        }
    }

    func testVariantNamesAreUniqueWithinAYear() {
        for year in 2017...2024 {
            let names = (TeslaRangeCatalog.variants(model: "Model 3", year: "\(year)") ?? []).map(\.name)
            XCTAssertEqual(names.count, Set(names).count, "\(year) has a duplicate variant name")
        }
    }
}
