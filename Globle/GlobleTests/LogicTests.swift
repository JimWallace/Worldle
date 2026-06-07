import XCTest
import UIKit
@testable import Globle

/// Search / autocomplete behavior.
final class SearchTests: XCTestCase {
    private let store = CountryStore.shared

    func testAliasesResolve() {
        XCTAssertEqual(store.search("usa").first?.id, "USA")
        XCTAssertEqual(store.search("holland").first?.id, "NLD")
        XCTAssertEqual(store.search("burma").first?.id, "MMR")
        XCTAssertEqual(store.search("england").first?.id, "GBR")
    }

    func testAccentInsensitive() {
        // "cote" should find Côte d'Ivoire.
        XCTAssertEqual(store.search("cote").first?.id, "CIV")
    }

    func testPrefixBeatsContains() {
        // A leading match for "ind" should rank India/Indonesia above "British Indian Ocean…".
        let top = store.search("ind").first?.id
        XCTAssertTrue(top == "IND" || top == "IDN", "got \(top ?? "nil")")
    }

    func testExclusionHidesGuessed() {
        XCTAssertFalse(store.search("france", excluding: ["FRA"]).contains { $0.id == "FRA" })
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(store.search("").isEmpty)
        XCTAssertTrue(store.search("   ").isEmpty)
    }
}

/// The daily puzzle selection.
final class DailyPuzzleTests: XCTestCase {
    private let store = CountryStore.shared
    private let cal = Calendar(identifier: .gregorian)

    private func day(_ offset: Int) -> Date {
        let start = cal.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        return cal.date(byAdding: .day, value: offset, to: start)!
    }

    func testDeterministicForSameDay() {
        let a = DailyPuzzle.target(from: store.targets, on: day(123), calendar: cal)
        let b = DailyPuzzle.target(from: store.targets, on: day(123), calendar: cal)
        XCTAssertEqual(a?.id, b?.id)
    }

    func testAlwaysEligible() {
        for offset in 0..<60 {
            let t = DailyPuzzle.target(from: store.targets, on: day(offset), calendar: cal)
            XCTAssertEqual(t?.target, true)
        }
    }

    func testCyclesThroughEveryTargetBeforeRepeating() {
        var seen: [String] = []
        for offset in 0..<store.targets.count {
            seen.append(DailyPuzzle.target(from: store.targets, on: day(offset), calendar: cal)!.id)
        }
        XCTAssertEqual(Set(seen).count, store.targets.count, "every target should appear exactly once per cycle")
    }
}

/// Distance + warmth mapping — the core feedback signal.
final class ProximityTests: XCTestCase {
    private let store = CountryStore.shared
    private func c(_ id: String) -> Country { store.country(id: id)! }

    func testHaversineKnownDistance() {
        // London → Paris ≈ 344 km.
        let d = Geo.haversineKm(lat1: 51.5074, lon1: -0.1278, lat2: 48.8566, lon2: 2.3522)
        XCTAssertEqual(d, 344, accuracy: 30)
    }

    func testTargetItselfIsZero() {
        let engine = ProximityEngine(target: c("FRA"))
        XCTAssertEqual(engine.distanceKm(to: c("FRA")), 0, accuracy: 0.001)
    }

    func testNeighborCloserThanFaraway() {
        let engine = ProximityEngine(target: c("FRA"))
        let germany = engine.distanceKm(to: c("DEU"))
        let china = engine.distanceKm(to: c("CHN"))
        XCTAssertLessThan(germany, 1000, "France and Germany share a border")
        XCTAssertLessThan(germany, china)
    }

    func testFarApartIsLarge() {
        // Mongolia and Chile are compact and nearly antipodal.
        let engine = ProximityEngine(target: c("MNG"))
        XCTAssertGreaterThan(engine.distanceKm(to: c("CHL")), 14000)
    }

    func testWarmthColorGetsRedderWhenCloser() {
        let near = Warmth.color(forDistanceKm: 100)
        let far = Warmth.color(forDistanceKm: 18000)
        var nr: CGFloat = 0, ng: CGFloat = 0, nb: CGFloat = 0, na: CGFloat = 0
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        near.getRed(&nr, green: &ng, blue: &nb, alpha: &na)
        far.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        XCTAssertGreaterThan(nr, fr, "closer should be redder")
        XCTAssertGreaterThan(fb, nb, "farther should be bluer")
    }

    func testWarmthLabels() {
        XCTAssertEqual(Warmth.label(forDistanceKm: 0).text, "Found it!")
        XCTAssertEqual(Warmth.label(forDistanceKm: 100).text, "Boiling")
        XCTAssertEqual(Warmth.label(forDistanceKm: 19000).text, "Freezing")
    }

    func testClosenessBounds() {
        XCTAssertEqual(Warmth.closeness(forDistanceKm: 0), 1, accuracy: 0.001)
        XCTAssertEqual(Warmth.closeness(forDistanceKm: 1_000_000), 0, accuracy: 0.001)
    }
}
