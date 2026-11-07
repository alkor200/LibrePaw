import Testing
@testable import TraccarKit

@Suite("TraccarGeofenceArea")
struct TraccarGeofenceAreaTests {
    @Test("circleWKT writes longitude before latitude (verified against a live server)")
    func circleWKTFormatsLongitudeFirst() {
        let wkt = TraccarGeofenceArea.circleWKT(centerLatitude: 51.36412, centerLongitude: 12.39587, radiusMeters: 150)
        #expect(wkt == "CIRCLE (12.39587 51.36412, 150.0)")
    }

    @Test("parseCircle round-trips what circleWKT produces")
    func parseCircleRoundTrips() throws {
        let wkt = TraccarGeofenceArea.circleWKT(centerLatitude: 51.36412, centerLongitude: 12.39587, radiusMeters: 150)
        let parsed = try #require(TraccarGeofenceArea.parseCircle(wkt))

        #expect(parsed.latitude == 51.36412)
        #expect(parsed.longitude == 12.39587)
        #expect(parsed.radiusMeters == 150)
    }

    @Test("parseCircle rejects non-circle WKT")
    func parseCircleRejectsOtherShapes() {
        #expect(TraccarGeofenceArea.parseCircle("POLYGON ((0 0, 1 1, 1 0, 0 0))") == nil)
        #expect(TraccarGeofenceArea.parseCircle("not wkt at all") == nil)
    }
}
