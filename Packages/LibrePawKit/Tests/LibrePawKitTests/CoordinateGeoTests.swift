import Foundation
import Testing
@testable import LibrePawKit

@Suite("Coordinate+Geo")
struct CoordinateGeoTests {
    @Test("Distance to self is zero")
    func distanceToSelfIsZero() {
        let point = Coordinate(latitude: 52.5200, longitude: 13.4050)
        #expect(point.distanceMeters(to: point) == 0)
    }

    @Test("Distance between Berlin and Munich is roughly 504 km")
    func distanceBetweenKnownCities() {
        let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)
        let munich = Coordinate(latitude: 48.1374, longitude: 11.5755)

        let distance = berlin.distanceMeters(to: munich)

        #expect((500_000...510_000).contains(distance))
    }

    @Test("A point exactly one degree of longitude east on the equator bears ~90 degrees")
    func bearingDueEast() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        let eastOfOrigin = Coordinate(latitude: 0, longitude: 1)

        let bearing = origin.initialBearingDegrees(to: eastOfOrigin)

        #expect(abs(bearing - 90) < 0.01)
    }

    @Test("A point due north bears 0 degrees")
    func bearingDueNorth() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        let northOfOrigin = Coordinate(latitude: 1, longitude: 0)

        let bearing = origin.initialBearingDegrees(to: northOfOrigin)

        #expect(abs(bearing - 0) < 0.01)
    }

    @Test("A point due south bears 180 degrees")
    func bearingDueSouth() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        let southOfOrigin = Coordinate(latitude: -1, longitude: 0)

        let bearing = origin.initialBearingDegrees(to: southOfOrigin)

        #expect(abs(bearing - 180) < 0.01)
    }

    @Test("Bearing is always normalized to [0, 360)")
    func bearingIsNormalized() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        let southWestOfOrigin = Coordinate(latitude: -1, longitude: -1)

        let bearing = origin.initialBearingDegrees(to: southWestOfOrigin)

        #expect(bearing >= 0 && bearing < 360)
        #expect(bearing > 180 && bearing < 270)
    }
}
