import Foundation

/// Great-circle math on `Coordinate`, used to power the "Find Pet" compass
/// view (see ADR-0010). Implemented with plain spherical trigonometry so
/// `ScentrailKit` never needs to import CoreLocation (see ADR-0005).
extension Coordinate {
    private static let earthRadiusMeters = 6_371_000.0

    /// Great-circle distance to another coordinate, in meters (haversine formula).
    public func distanceMeters(to other: Coordinate) -> Double {
        let lat1 = latitude.radians
        let lat2 = other.latitude.radians
        let deltaLat = (other.latitude - latitude).radians
        let deltaLon = (other.longitude - longitude).radians

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(a.squareRoot(), (1 - a).squareRoot())

        return Self.earthRadiusMeters * c
    }

    /// Initial compass bearing to another coordinate, in degrees from true
    /// north, normalized to `[0, 360)`.
    public func initialBearingDegrees(to other: Coordinate) -> Double {
        let lat1 = latitude.radians
        let lat2 = other.latitude.radians
        let deltaLon = (other.longitude - longitude).radians

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x).degrees

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
