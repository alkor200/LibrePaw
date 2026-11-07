import Foundation
import Testing
@testable import ScentrailKit

@Suite("Excursion")
struct ExcursionTests {
    private func excursion(startTime: Date, endTime: Date?, distanceMeters: Double?) -> Excursion {
        Excursion(
            id: 1,
            startTime: startTime,
            endTime: endTime,
            startCoordinate: nil,
            endCoordinate: nil,
            distanceMeters: distanceMeters
        )
    }

    @Test("A normal walking pace is not flagged as a vehicle trip")
    func walkingPaceIsNotFlagged() {
        let now = Date.now
        // 800m in 15 minutes ≈ 3.2 km/h — a relaxed walk.
        let walk = excursion(startTime: now.addingTimeInterval(-900), endTime: now, distanceMeters: 800)

        #expect(walk.isLikelyVehicleTrip == false)
    }

    @Test("A sustained car-speed average is flagged as a likely vehicle trip")
    func carPaceIsFlagged() {
        let now = Date.now
        // 5km in 10 minutes = 30 km/h average — no dog sustains that home-to-home.
        let drive = excursion(startTime: now.addingTimeInterval(-600), endTime: now, distanceMeters: 5_000)

        #expect(drive.isLikelyVehicleTrip == true)
    }

    @Test("An ongoing excursion is never flagged — there's no average speed yet")
    func ongoingExcursionIsNeverFlagged() {
        let ongoing = excursion(startTime: .now.addingTimeInterval(-600), endTime: nil, distanceMeters: 5_000)

        #expect(ongoing.averageSpeedKilometersPerHour == nil)
        #expect(ongoing.isLikelyVehicleTrip == false)
    }

    @Test("An excursion with no measurable distance is never flagged")
    func noDistanceIsNeverFlagged() {
        let now = Date.now
        let unmeasured = excursion(startTime: now.addingTimeInterval(-600), endTime: now, distanceMeters: nil)

        #expect(unmeasured.isLikelyVehicleTrip == false)
    }
}
