import UIKit

/// Computes how close a guessed country is to the mystery country and turns that
/// distance into the warm/cold colors and words that drive the whole game.
final class ProximityEngine {
    let target: Country
    private let targetSamples: [(lat: Double, lon: Double)]
    private var cache: [String: Double] = [:]

    init(target: Country) {
        self.target = target
        self.targetSamples = target.boundarySamples()
    }

    /// Minimum distance (km) between the borders of `country` and the mystery country.
    /// Bordering countries come out near 0 (the "hottest"); antipodes near 20,000 km.
    func distanceKm(to country: Country) -> Double {
        if country.id == target.id { return 0 }
        if let cached = cache[country.id] { return cached }
        let value = Self.minBorderDistanceKm(
            country.boundarySamples(), targetSamples,
            fallbackA: (country.lat, country.lon),
            fallbackB: (target.lat, target.lon))
        cache[country.id] = value
        return value
    }

    static func minBorderDistanceKm(_ a: [(lat: Double, lon: Double)],
                                    _ b: [(lat: Double, lon: Double)],
                                    fallbackA: (lat: Double, lon: Double),
                                    fallbackB: (lat: Double, lon: Double)) -> Double {
        guard !a.isEmpty, !b.isEmpty else {
            return Geo.haversineKm(lat1: fallbackA.lat, lon1: fallbackA.lon,
                                   lat2: fallbackB.lat, lon2: fallbackB.lon)
        }
        var best = Double.greatestFiniteMagnitude
        for pa in a {
            for pb in b {
                let d = Geo.haversineKm(lat1: pa.lat, lon1: pa.lon, lat2: pb.lat, lon2: pb.lon)
                if d < best {
                    best = d
                    if best < 1 { return 0 } // sharing a border — as hot as it gets
                }
            }
        }
        return best
    }
}

/// Stateless mapping from a distance to its color and kid-readable warmth label.
enum Warmth {
    /// Vivid warm→cold gradient: red (touching) → orange → gold → green → blue (far away).
    private static let stops: [(km: Double, r: Double, g: Double, b: Double)] = [
        (0,     0.86, 0.10, 0.12),
        (500,   0.96, 0.30, 0.12),
        (1500,  0.99, 0.55, 0.12),
        (3000,  0.99, 0.80, 0.20),
        (5000,  0.72, 0.82, 0.26),
        (7500,  0.30, 0.72, 0.56),
        (11000, 0.20, 0.52, 0.82),
        (20015, 0.17, 0.24, 0.55),
    ]

    static func color(forDistanceKm km: Double) -> UIColor {
        let d = max(0, km)
        if d <= stops.first!.km { return makeColor(stops.first!) }
        if d >= stops.last!.km { return makeColor(stops.last!) }
        for i in 1..<stops.count {
            let lo = stops[i - 1], hi = stops[i]
            if d <= hi.km {
                let t = (d - lo.km) / (hi.km - lo.km)
                return UIColor(red: CGFloat(lo.r + (hi.r - lo.r) * t),
                               green: CGFloat(lo.g + (hi.g - lo.g) * t),
                               blue: CGFloat(lo.b + (hi.b - lo.b) * t), alpha: 1)
            }
        }
        return .gray
    }

    private static func makeColor(_ stop: (km: Double, r: Double, g: Double, b: Double)) -> UIColor {
        UIColor(red: CGFloat(stop.r), green: CGFloat(stop.g), blue: CGFloat(stop.b), alpha: 1)
    }

    /// A child-friendly description of how close the guess is.
    static func label(forDistanceKm km: Double) -> (text: String, emoji: String) {
        switch km {
        case ..<1:     return ("Found it!", "🎯")
        case ..<250:   return ("Boiling",   "🔥")
        case ..<1000:  return ("Very hot",  "🥵")
        case ..<2500:  return ("Hot",       "☀️")
        case ..<4500:  return ("Warm",      "🙂")
        case ..<7000:  return ("Cool",      "🌤️")
        case ..<10000: return ("Cold",      "🥶")
        default:       return ("Freezing",  "❄️")
        }
    }

    /// 0 (far) … 1 (touching) — handy for progress bars / meters.
    static func closeness(forDistanceKm km: Double) -> Double {
        max(0, min(1, 1 - km / Geo.maxDistanceKm))
    }
}
