import Foundation

/// Great-circle math on `Coordinate`, used to power the "Find Pet" compass
/// view (see ADR-0010). Implemented with plain spherical trigonometry so
/// `LibrePawKit` never needs to import CoreLocation (see ADR-0005).
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

    /// The point `distanceMeters` away from this one, along `bearingDegrees`
    /// (from true north). The inverse of `distanceMeters(to:)`/
    /// `initialBearingDegrees(to:)`: given a center, a distance, and a
    /// bearing, finds the destination, rather than the distance/bearing
    /// between two known points.
    ///
    /// Added to approximate a geofence's circle as a polygon of points
    /// around its center: MapLibre's circle-radius style property is in
    /// screen pixels, not real-world meters, so it can't draw a circle that
    /// stays the correct ground size across zoom levels the way MapKit's
    /// `MapCircle(center:radius:)` did (see ADR-0028).
    public func destination(distanceMeters: Double, bearingDegrees: Double) -> Coordinate {
        let angularDistance = distanceMeters / Self.earthRadiusMeters
        let bearing = bearingDegrees.radians
        let lat1 = latitude.radians
        let lon1 = longitude.radians

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return Coordinate(latitude: lat2.degrees, longitude: lon2.degrees)
    }

    /// A closed ring of `segments` points approximating a circle of
    /// `radiusMeters` around this coordinate, suitable for rendering as a
    /// polygon (first and last point identical, as GeoJSON/MapLibre
    /// polygons require).
    public func circlePolygon(radiusMeters: Double, segments: Int = 64) -> [Coordinate] {
        let points = (0..<segments).map { index in
            destination(distanceMeters: radiusMeters, bearingDegrees: Double(index) / Double(segments) * 360)
        }
        return points + [points[0]]
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
