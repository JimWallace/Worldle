import XCTest
@testable import Globle

/// Validates the bundled country data and the model decoding.
final class DataTests: XCTestCase {
    private let store = CountryStore.shared

    func testCountsMatchData() {
        XCTAssertEqual(store.all.count, 242, "Expected every Natural Earth 50m country/territory")
        XCTAssertEqual(store.targets.count, 199, "Expected every sovereign country as a daily target")
        XCTAssertTrue(store.targets.allSatisfy { $0.target })
    }

    func testEveryCountryHasGeometryAndLabelPoint() {
        for country in store.all {
            XCTAssertFalse(country.geometry.isEmpty, "\(country.name) has no geometry")
            XCTAssertTrue((-90.0...90.0).contains(country.lat), "\(country.name) bad lat")
            XCTAssertTrue((-180.0...180.0).contains(country.lon), "\(country.name) bad lon")
        }
    }

    func testKnownCountry() {
        let france = store.country(id: "FRA")
        XCTAssertEqual(france?.name, "France")
        XCTAssertEqual(france?.iso2, "FR")
        XCTAssertEqual(france?.flag, "🇫🇷")
        XCTAssertEqual(france?.target, true)
    }

    func testMicrostatesArePlayableTargets() {
        for id in ["MCO", "VAT", "TUV", "NRU", "MHL", "SMR"] {
            let c = store.country(id: id)
            XCTAssertNotNil(c, "missing \(id)")
            XCTAssertEqual(c?.target, true, "\(id) should be a daily target")
        }
    }

    func testDependenciesAreGuessableButNotTargets() {
        for id in ["GRL", "PRI", "HKG"] {        // Greenland, Puerto Rico, Hong Kong
            XCTAssertNotNil(store.country(id: id))
            XCTAssertEqual(store.country(id: id)?.target, false)
        }
    }

    func testFlagFallbackForMissingIso() {
        let mystery = Country(id: "ZZ", name: "Nowhere", iso2: "", lon: 0, lat: 0,
                              pop: 0, continent: "", sovereign: false, target: false,
                              aliases: [], geometry: [])
        XCTAssertEqual(mystery.flag, "🌍")
    }
}
