import Foundation
import Testing
import TraccarKit
@testable import LibrePawKit

@Suite("TraccarPetRepository.firstHomecomingPause")
struct FirstHomecomingPauseTests {
    private let homeCenter = Coordinate(latitude: 52.5200, longitude: 13.4050)
    // Roughly 2km away, clearly outside any reasonable proximity slack.
    private let farAway = Coordinate(latitude: 52.5380, longitude: 13.4050)

    private func home(id: Int = 1, radiusMeters: Double = 50) -> HomeGeofence {
        HomeGeofence(id: id, name: "Home", center: homeCenter, radiusMeters: radiusMeters)
    }

    private func position(id: Int, coordinate: Coordinate, minutesFromNow: Double) -> TraccarPosition {
        TraccarPosition(
            id: id,
            deviceId: 1,
            fixTime: Date.now.addingTimeInterval(minutesFromNow * 60),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            speed: 0,
            course: 0,
            address: nil,
            attributes: [:]
        )
    }

    @Test("A position at home followed by a long silence closes the excursion there")
    func closesOnNearHomeThenQuiet() {
        let trail = [
            position(id: 1, coordinate: farAway, minutesFromNow: -60),
            position(id: 2, coordinate: homeCenter, minutesFromNow: -40)
            // Nothing after this: the device went quiet right after arriving.
        ]

        let result = TraccarPetRepository.firstHomecomingPause(in: trail, homes: [home()])

        #expect(result?.homeID == 1)
        #expect(result?.fixTime == trail[1].fixTime)
    }

    @Test("A position just outside the radius but within the proximity slack still counts")
    func closesWithinSlackBeyondRadius() {
        // ~80m north of the home center: outside a 50m radius, but well
        // within the default 100m slack.
        let justOutside = Coordinate(latitude: homeCenter.latitude + 0.00072, longitude: homeCenter.longitude)
        let trail = [position(id: 1, coordinate: justOutside, minutesFromNow: -40)]

        let result = TraccarPetRepository.firstHomecomingPause(in: trail, homes: [home(radiusMeters: 50)])

        #expect(result != nil)
    }

    @Test("A position well beyond the proximity slack never counts, however long the silence")
    func ignoresPositionsFarFromHome() {
        let trail = [position(id: 1, coordinate: farAway, minutesFromNow: -40)]

        let result = TraccarPetRepository.firstHomecomingPause(in: trail, homes: [home()])

        #expect(result == nil)
    }

    @Test("Passing near home without stopping (another position soon after) doesn't close it")
    func ignoresABriefPassNearHome() {
        let trail = [
            position(id: 1, coordinate: homeCenter, minutesFromNow: -40),
            // Only 2 minutes later, still moving, nowhere near the quiet
            // gap threshold - a pass-by, not a stop.
            position(id: 2, coordinate: farAway, minutesFromNow: -38)
        ]

        let result = TraccarPetRepository.firstHomecomingPause(in: trail, homes: [home()])

        #expect(result == nil)
    }

    @Test("The earliest qualifying homecoming pause wins, not a later one")
    func picksTheEarliestPause() {
        let trail = [
            position(id: 1, coordinate: homeCenter, minutesFromNow: -60)
            // Quiet for the rest of the (empty) trail - qualifies immediately.
        ]

        let result = TraccarPetRepository.firstHomecomingPause(in: trail, homes: [home()])

        #expect(result?.fixTime == trail[0].fixTime)
    }

    @Test("Checks every home, not just the first, and reports whichever one matched")
    func matchesAnyConfiguredHome() {
        let cabinCenter = Coordinate(latitude: 52.4100, longitude: 13.0500)
        let cabin = HomeGeofence(id: 2, name: "Cabin", center: cabinCenter, radiusMeters: 60)
        let trail = [position(id: 1, coordinate: cabinCenter, minutesFromNow: -40)]

        let result = TraccarPetRepository.firstHomecomingPause(in: trail, homes: [home(), cabin])

        #expect(result?.homeID == 2)
    }

    @Test("A gap just under the default 10 minute threshold doesn't count as quiet yet")
    func gapJustUnderDefaultThresholdDoesNotQualify() {
        let trail = [
            position(id: 1, coordinate: homeCenter, minutesFromNow: -40),
            position(id: 2, coordinate: farAway, minutesFromNow: -40 + 9.9)
        ]

        let result = TraccarPetRepository.firstHomecomingPause(in: trail, homes: [home()])

        #expect(result == nil)
    }

    @Test("A gap at or just over the default 10 minute threshold counts as quiet")
    func gapAtDefaultThresholdQualifies() {
        let trail = [
            position(id: 1, coordinate: homeCenter, minutesFromNow: -40),
            position(id: 2, coordinate: farAway, minutesFromNow: -40 + 10.0)
        ]

        let result = TraccarPetRepository.firstHomecomingPause(in: trail, homes: [home()])

        #expect(result?.fixTime == trail[0].fixTime)
    }

    @Test("An empty trail has no homecoming pause")
    func handlesEmptyTrail() {
        let result = TraccarPetRepository.firstHomecomingPause(in: [], homes: [home()])
        #expect(result == nil)
    }

    @Test("No configured homes means nothing can ever match")
    func handlesNoHomes() {
        let trail = [position(id: 1, coordinate: homeCenter, minutesFromNow: -40)]
        let result = TraccarPetRepository.firstHomecomingPause(in: trail, homes: [])
        #expect(result == nil)
    }

    @Test("A homecoming pause earlier than a real enter event is preferred")
    func prefersGenuinelyEarlierHomecoming() {
        let homecoming = (fixTime: Date.now.addingTimeInterval(-60 * 60), homeID: 1)
        let fetchedEndTime = Date.now

        #expect(TraccarPetRepository.shouldPreferHomecoming(homecoming, overFetchedEndTime: fetchedEndTime))
    }

    @Test("A homecoming pause tied with a real enter event's own time is not preferred")
    func doesNotOverrideOnATie() {
        let fetchedEndTime = Date.now
        let homecoming = (fixTime: fetchedEndTime, homeID: 2)

        #expect(!TraccarPetRepository.shouldPreferHomecoming(homecoming, overFetchedEndTime: fetchedEndTime))
    }

    @Test("A homecoming pause is always preferred when there is no real enter event yet")
    func prefersHomecomingWhenStillOpen() {
        let homecoming = (fixTime: Date.now, homeID: 1)

        #expect(TraccarPetRepository.shouldPreferHomecoming(homecoming, overFetchedEndTime: nil))
    }
}
