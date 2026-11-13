import Foundation
import Testing
import TraccarKit
@testable import LibrePawKit

/// Shaped like Phoebe's real 2026-11-13 trail (see ADR-0029): one exit at
/// 08:39 and one enter at 16:12 for two separate walks, the tracker having
/// fallen asleep 42m from the center of a 40m home in between and woken up
/// 126m away. Only the times and distances from home are real, the home
/// itself is an arbitrary made-up location, never the real one.
@Suite("TraccarPetRepository.splitIntoExcursions")
struct SplitIntoExcursionsTests {
    private let homeCenter = Coordinate(latitude: 51.3091, longitude: 12.4178)
    private let home = HomeGeofence(id: 24, name: "Home", center: Coordinate(latitude: 51.3091, longitude: 12.4178), radiusMeters: 40)
    private let day = Date(timeIntervalSince1970: 1_794_556_800) // 2026-11-13 00:00 UTC

    private func time(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        day.addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60 + second))
    }

    /// A position `meters` due north of the home's center.
    private func position(_ id: Int, _ fixTime: Date, meters: Double) -> TraccarPosition {
        TraccarPosition(
            id: id,
            deviceId: 1,
            fixTime: fixTime,
            latitude: homeCenter.latitude + meters / 111_320,
            longitude: homeCenter.longitude,
            speed: 0,
            course: 0,
            address: nil,
            attributes: [:]
        )
    }

    private var exit: TraccarEvent {
        TraccarEvent(id: 281, type: TraccarEvent.EventType.geofenceExit, eventTime: time(8, 39, 36), deviceId: 1, geofenceId: 24)
    }

    private var enter: TraccarEvent {
        TraccarEvent(id: 305, type: TraccarEvent.EventType.geofenceEnter, eventTime: time(16, 12, 18), deviceId: 1, geofenceId: 24)
    }

    // Thinned out from the real ~30 second fixes, but never with a gap of
    // five minutes or more near home, which would read as the tracker
    // falling asleep there.
    private var morningWalk: [TraccarPosition] {
        [
            position(1803, time(8, 39, 36), meters: 85),
            position(1804, time(8, 40, 6), meters: 96),
            position(1806, time(8, 41, 6), meters: 116),
            position(1813, time(8, 44, 38), meters: 239),
            position(1833, time(8, 56, 42), meters: 400),
            position(1853, time(9, 10, 15), meters: 171),
            position(1863, time(9, 15, 47), meters: 112),
            position(1866, time(9, 17, 17), meters: 53),
            // Asleep from here, 2m short of the 40m boundary.
            position(1867, time(9, 17, 47), meters: 42),
            position(1870, time(9, 17, 47), meters: 42)
        ]
    }

    private var afternoonWalk: [TraccarPosition] {
        [
            // Awake again, already outside, so no exit event.
            position(1871, time(15, 12, 0), meters: 126),
            position(1873, time(15, 13, 0), meters: 170),
            position(1903, time(15, 34, 7), meters: 570),
            position(1953, time(16, 5, 16), meters: 307),
            position(1963, time(16, 10, 48), meters: 113),
            position(1965, time(16, 11, 48), meters: 51),
            position(1966, time(16, 12, 18), meters: 23)
        ]
    }

    @Test("Once Traccar closes the pair, both walks come out as separate excursions")
    func closedPairSplitsIntoBothWalks() throws {
        let excursions = TraccarPetRepository.splitIntoExcursions(
            exit: exit,
            enter: enter,
            trail: morningWalk + afternoonWalk,
            homes: [home],
            trailEndTime: enter.eventTime
        )

        try #require(excursions.count == 2)
        let (morning, afternoon) = (excursions[0], excursions[1])

        #expect(morning.id == 281)
        #expect(morning.startTime == time(8, 39, 36))
        #expect(morning.endTime == time(9, 17, 47))
        #expect(morning.endHomeID == 24)

        #expect(afternoon.id == -1871)
        #expect(afternoon.startTime == time(15, 12, 0))
        #expect(afternoon.endTime == time(16, 12, 18))
        #expect(afternoon.startHomeID == 24)
        #expect(afternoon.endHomeID == 24)
        // Each walk's distance only covers its own positions: 85 to 400 and
        // back to 42m is 673m, 126 to 570 and back to 23m is 991m.
        #expect(abs((morning.distanceMeters ?? 0) - 673) < 5)
        #expect(abs((afternoon.distanceMeters ?? 0) - 991) < 5)
    }

    @Test("During the afternoon walk, the morning one is closed and the afternoon one is ongoing")
    func openPairMidSecondWalk() throws {
        let now = time(15, 34, 30)
        let soFar = morningWalk + afternoonWalk.filter { $0.fixTime <= now }

        let excursions = TraccarPetRepository.splitIntoExcursions(exit: exit, enter: nil, trail: soFar, homes: [home], trailEndTime: now)

        try #require(excursions.count == 2)
        #expect(excursions[0].endTime == time(9, 17, 47))
        #expect(excursions[1].id == -1871)
        #expect(excursions[1].isOngoing)
    }

    @Test("Between the walks, only the morning walk exists, closed at the pause")
    func openPairBetweenWalks() {
        let excursions = TraccarPetRepository.splitIntoExcursions(
            exit: exit,
            enter: nil,
            trail: morningWalk,
            homes: [home],
            trailEndTime: time(10, 0)
        )

        #expect(excursions.map(\.id) == [281])
        #expect(excursions.first?.endTime == time(9, 17, 47))
    }

    @Test("A signal dead spot by the front door right after leaving doesn't split off a stub")
    func deadSpotBeforeTheWalkKeepsOneExcursion() throws {
        let leave = time(8, 0)
        let exit = TraccarEvent(id: 1, type: TraccarEvent.EventType.geofenceExit, eventTime: leave, deviceId: 1, geofenceId: 24)
        let enter = TraccarEvent(id: 2, type: TraccarEvent.EventType.geofenceEnter, eventTime: time(9, 0), deviceId: 1, geofenceId: 24)
        let trail = [
            position(10, time(8, 0, 0), meters: 50),
            // Six minutes without a fix, still by the door.
            position(11, time(8, 0, 30), meters: 60),
            position(12, time(8, 6, 30), meters: 150),
            position(13, time(8, 30), meters: 600),
            position(14, time(9, 0), meters: 20)
        ]

        let excursions = TraccarPetRepository.splitIntoExcursions(exit: exit, enter: enter, trail: trail, homes: [home], trailEndTime: enter.eventTime)

        // One excursion, still the exit's own, starting where the walk
        // actually got going after the dead spot.
        #expect(excursions.map(\.id) == [1])
        #expect(excursions.first?.startTime == time(8, 6, 30))
        #expect(excursions.first?.endTime == enter.eventTime)
        _ = leave
    }

    @Test("A jitter exit at the fence followed by a night at home doesn't stretch into the next day's walk")
    func jitterExitThenNightAtHome() throws {
        // Phoebe's real 2026-11-10/11 trail: "left" at 48m from a 40m home,
        // slept there, briefly reported 86 to 123m in the evening (still
        // within the slack), slept again, and only really left at 12:59
        // the next day.
        let nextDay = day.addingTimeInterval(86_400)
        let exit = TraccarEvent(id: 197, type: TraccarEvent.EventType.geofenceExit, eventTime: time(14, 17), deviceId: 1, geofenceId: 24)
        let enter = TraccarEvent(id: 209, type: TraccarEvent.EventType.geofenceEnter, eventTime: nextDay.addingTimeInterval(13 * 3_600 + 30 * 60 + 45), deviceId: 1, geofenceId: 24)
        let trail = [
            position(1, time(14, 17), meters: 48),
            position(2, time(22, 55, 35), meters: 86),
            position(3, time(22, 56, 36), meters: 123),
            position(4, nextDay.addingTimeInterval(12 * 3_600 + 59 * 60 + 35), meters: 120),
            position(41, nextDay.addingTimeInterval(13 * 3_600 + 0 * 60 + 5), meters: 160),
            position(5, nextDay.addingTimeInterval(13 * 3_600 + 5 * 60 + 37), meters: 413),
            position(6, nextDay.addingTimeInterval(13 * 3_600 + 13 * 60 + 10), meters: 599),
            position(7, nextDay.addingTimeInterval(13 * 3_600 + 28 * 60 + 44), meters: 125),
            position(8, enter.eventTime, meters: 14)
        ]

        let excursions = TraccarPetRepository.splitIntoExcursions(exit: exit, enter: enter, trail: trail, homes: [home], trailEndTime: enter.eventTime)

        try #require(excursions.count == 1)
        #expect(excursions[0].id == 197)
        #expect(excursions[0].startTime == trail[3].fixTime)
        #expect(excursions[0].endTime == enter.eventTime)
    }

    @Test("Pottering about just outside the fence after coming home isn't a new walk")
    func stayingNearHomeAfterThePauseIsNoNewWalk() {
        let garden = [
            position(1900, time(12, 0), meters: 60),
            position(1901, time(12, 0, 30), meters: 75)
        ]

        let excursions = TraccarPetRepository.splitIntoExcursions(
            exit: exit,
            enter: nil,
            trail: morningWalk + garden,
            homes: [home],
            trailEndTime: time(13, 0)
        )

        #expect(excursions.map(\.id) == [281])
    }

    @Test("An ordinary walk ending with a real enter event stays one excursion")
    func ordinaryWalkIsUnchanged() {
        let excursions = TraccarPetRepository.splitIntoExcursions(
            exit: TraccarEvent(id: 1, type: TraccarEvent.EventType.geofenceExit, eventTime: time(15, 12), deviceId: 1, geofenceId: 24),
            enter: enter,
            trail: afternoonWalk,
            homes: [home],
            trailEndTime: enter.eventTime
        )

        #expect(excursions.map(\.id) == [1])
        #expect(excursions.first?.endTime == enter.eventTime)
    }
}

@Suite("TraccarPetRepository.mergeExcursions with provisional excursions")
struct ProvisionalExcursionMergeTests {
    @Test("An excursion split out of a still-open pair is shown but neither cached nor advancing the watermark")
    func provisionalExcursionsAreNotCached() {
        let now = Date.now
        let watermark = now.addingTimeInterval(-86_400)
        let cached = CachedExcursions(excursions: [], coveredFrom: now.addingTimeInterval(-30 * 86_400), cachedThroughEndTime: watermark)
        let closedAtPause = Excursion(
            id: 281,
            startTime: now.addingTimeInterval(-7 * 3_600),
            endTime: now.addingTimeInterval(-6 * 3_600),
            startCoordinate: nil,
            endCoordinate: nil,
            distanceMeters: 800
        )

        let (all, newCache) = TraccarPetRepository.mergeExcursions(
            cached: cached,
            freshExcursions: [closedAtPause],
            provisionalIDs: [281],
            liveFrom: watermark
        )

        #expect(all.map(\.id) == [281])
        #expect(newCache.excursions.isEmpty)
        #expect(newCache.cachedThroughEndTime == watermark)
    }

    @Test("A request starting after the watermark still fetches from the watermark")
    func liveFetchStartsAtWatermarkEvenForALaterFrom() {
        let now = Date.now
        let watermark = now.addingTimeInterval(-86_400)
        let cached = CachedExcursions(excursions: [], coveredFrom: now.addingTimeInterval(-30 * 86_400), cachedThroughEndTime: watermark)

        #expect(TraccarPetRepository.liveFetchStart(cached: cached, from: now.addingTimeInterval(-3_600)) == watermark)
    }
}
