import Foundation

/// A country loaded from the bundled `countries.json` (derived from Natural Earth 110m data).
///
/// Geometry is a GeoJSON-style MultiPolygon stored as nested arrays for compact decoding:
/// `geometry[polygon][ring][point]` where each `point` is `[longitude, latitude]` in degrees.
struct Country: Codable, Identifiable, Hashable {
    let id: String            // ISO A3 code (e.g. "FRA") — stable unique id
    let name: String          // Kid-friendly display name (e.g. "France")
    let iso2: String          // ISO A2 code (e.g. "FR"); "" when unknown
    let lon: Double           // Label point longitude (good interior point)
    let lat: Double           // Label point latitude
    let pop: Int              // Population estimate
    let continent: String     // Continent name (used for gentle hints)
    let sovereign: Bool       // Whether this is a self-governing sovereign state
    let target: Bool          // Eligible to be a daily mystery country
    let aliases: [String]     // Lowercased search tokens (name + alternates like "usa")
    let geometry: [[[[Double]]]]

    static func == (lhs: Country, rhs: Country) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Country {
    /// The country's flag as an emoji, or a globe when the ISO code is unknown.
    var flag: String {
        guard iso2.count == 2 else { return "🌍" }
        let base: UInt32 = 0x1F1E6 // Regional Indicator Symbol "A"
        var scalars = String.UnicodeScalarView()
        for ch in iso2.uppercased().unicodeScalars {
            guard ch.value >= 65, ch.value <= 90,
                  let scalar = Unicode.Scalar(base + (ch.value - 65)) else { return "🌍" }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Label point as (latitude, longitude) in degrees.
    var labelCoordinate: (lat: Double, lon: Double) { (lat, lon) }

    /// All boundary points across every polygon and ring, as (lat, lon) pairs.
    /// Used for the min-border distance calculation. Subsampled for speed.
    func boundarySamples(maxPoints: Int = 220) -> [(lat: Double, lon: Double)] {
        var pts: [(lat: Double, lon: Double)] = []
        for polygon in geometry {
            for ring in polygon {
                for point in ring where point.count == 2 {
                    pts.append((lat: point[1], lon: point[0]))
                }
            }
        }
        guard pts.count > maxPoints else { return pts }
        // Even stride so we keep a representative outline.
        let stride = Double(pts.count) / Double(maxPoints)
        var sampled: [(lat: Double, lon: Double)] = []
        sampled.reserveCapacity(maxPoints)
        var acc = 0.0
        var nextIndex = 0
        while nextIndex < pts.count {
            sampled.append(pts[nextIndex])
            acc += stride
            nextIndex = Int(acc)
        }
        return sampled
    }
}
