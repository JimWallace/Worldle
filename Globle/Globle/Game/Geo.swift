import Foundation
import simd

/// Geographic math helpers shared by the game logic and the globe renderer.
enum Geo {
    static let earthRadiusKm = 6371.0
    /// Roughly the farthest two points on Earth can be (antipodes ≈ half the circumference).
    static let maxDistanceKm = 20_015.0

    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// Great-circle distance in kilometres between two lat/lon points (haversine).
    static func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = radians(lat2 - lat1)
        let dLon = radians(lon2 - lon1)
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(radians(lat1)) * cos(radians(lat2)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(a)))
    }

    /// Convert lat/lon (degrees) to a unit vector on the globe.
    ///
    /// Convention used everywhere in the app: y is up (north), `lon = 0, lat = 0` points
    /// toward +Z (the camera). East is +X, so the map reads correctly (east on the right).
    static func unitVector(latDeg: Double, lonDeg: Double) -> SIMD3<Float> {
        let lat = Float(radians(latDeg))
        let lon = Float(radians(lonDeg))
        return SIMD3<Float>(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
    }

    /// Orientation that rotates the point at (lat, lon) to face the camera (+Z).
    /// Derivation: yaw by -lon about Y brings the point onto the prime meridian,
    /// then pitch by +lat about X brings it down to the equator-front (+Z).
    static func orientationToFace(latDeg: Double, lonDeg: Double) -> simd_quatf {
        let yaw = simd_quatf(angle: Float(radians(-lonDeg)), axis: SIMD3<Float>(0, 1, 0))
        let pitch = simd_quatf(angle: Float(radians(latDeg)), axis: SIMD3<Float>(1, 0, 0))
        return pitch * yaw
    }
}
