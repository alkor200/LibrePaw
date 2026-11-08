import Testing
@testable import TraccarKit

@Suite("TraccarGeofenceArea")
struct TraccarGeofenceAreaTests {
    @Test("circleWKT writes latitude before longitude, matching Traccar's own GeofenceCircle source")
    func circleWKTFormatsLatitudeFirst() {
        let wkt = TraccarGeofenceArea.circleWKT(centerLatitude: 51.36412, centerLongitude: 12.39587, radiusMeters: 150)
        #expect(wkt == "CIRCLE (51.36412 12.39587, 150.0)")
    }

    @Test("parseCircle round-trips what circleWKT produces")
    func parseCircleRoundTrips() throws {
        let wkt = TraccarGeofenceArea.circleWKT(centerLatitude: 51.36412, centerLongitude: 12.39587, radiusMeters: 150)
        let parsed = try #require(TraccarGeofenceArea.parseCircle(wkt))

        #expect(parsed.latitude == 51.36412)
        #expect(parsed.longitude == 12.39587)
        #expect(parsed.radiusMeters == 150)
    }

    @Test("parseCircle reads a fixed, independently-written WKT string correctly")
    func parseCircleReadsIndependentFixture() throws {
        // Deliberately not derived from circleWKT, a round-trip test alone
        // previously hid a lat/lon order bug because both functions shared
        // the same (wrong) assumption. This pins the format against a
        // literal string matching Traccar's own GeofenceCircle.toWkt output.
        let parsed = try #require(TraccarGeofenceArea.parseCircle("CIRCLE (51.31 12.42, 80)"))
        #expect(parsed.latitude == 51.31)
        #expect(parsed.longitude == 12.42)
        #expect(parsed.radiusMeters == 80)
    }

    @Test("parseCircle rejects non-circle WKT")
    func parseCircleRejectsOtherShapes() {
        #expect(TraccarGeofenceArea.parseCircle("POLYGON ((0 0, 1 1, 1 0, 0 0))") == nil)
        #expect(TraccarGeofenceArea.parseCircle("not wkt at all") == nil)
    }
}
