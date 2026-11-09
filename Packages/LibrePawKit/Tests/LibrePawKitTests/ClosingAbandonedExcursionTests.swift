import Foundation
import Testing
import TraccarKit
@testable import LibrePawKit

@Suite("TraccarPetRepository.closingAbandonedExcursion")
struct ClosingAbandonedExcursionTests {
    private func excursion(id: Int, startSecondsAgo: TimeInterval, endSecondsAgo: TimeInterval?) -> Excursion {
        Excursion(
            id: id,
            startTime: Date.now.addingTimeInterval(-startSecondsAgo),
            endTime: endSecondsAgo.map { Date.now.addingTimeInterval(-$0) },
            startCoordinate: nil,
            endCoordinate: nil,
            distanceMeters: nil
        )
    }

    @Test("An ongoing excursion closes at the device's last update once it goes offline")
    func closesWhenDeviceOffline() {
        let ongoing = excursion(id: 1, startSecondsAgo: 3_600, endSecondsAgo: nil)
        let lastUpdate = Date.now.addingTimeInterval(-1_800)

        let result = TraccarPetRepository.closingAbandonedExcursion(
            in: [ongoing],
            deviceStatus: .offline,
            deviceLastUpdate: lastUpdate
        )

        #expect(result.count == 1)
        #expect(result[0].endTime == lastUpdate)
        #expect(!result[0].isOngoing)
    }

    @Test("A still-online device leaves the excursion ongoing")
    func leavesOngoingWhileOnline() {
        let ongoing = excursion(id: 1, startSecondsAgo: 3_600, endSecondsAgo: nil)

        let result = TraccarPetRepository.closingAbandonedExcursion(
            in: [ongoing],
            deviceStatus: .online,
            deviceLastUpdate: Date.now
        )

        #expect(result[0].isOngoing)
    }

    @Test("No lastUpdate at all leaves the excursion ongoing")
    func leavesOngoingWithNoLastUpdate() {
        let ongoing = excursion(id: 1, startSecondsAgo: 3_600, endSecondsAgo: nil)

        let result = TraccarPetRepository.closingAbandonedExcursion(
            in: [ongoing],
            deviceStatus: .offline,
            deviceLastUpdate: nil
        )

        #expect(result[0].isOngoing)
    }

    @Test("A device that's been offline since before the excursion started doesn't close it")
    func ignoresStaleLastUpdate() {
        let ongoing = excursion(id: 1, startSecondsAgo: 1_800, endSecondsAgo: nil)
        // The device's last report predates the walk even starting, e.g. a
        // leftover status from a much earlier outage, not evidence the pet
        // is back.
        let staleLastUpdate = Date.now.addingTimeInterval(-7_200)

        let result = TraccarPetRepository.closingAbandonedExcursion(
            in: [ongoing],
            deviceStatus: .offline,
            deviceLastUpdate: staleLastUpdate
        )

        #expect(result[0].isOngoing)
    }

    @Test("An already-completed excursion is left untouched")
    func leavesCompletedExcursionsAlone() {
        let completed = excursion(id: 1, startSecondsAgo: 7_200, endSecondsAgo: 3_600)

        let result = TraccarPetRepository.closingAbandonedExcursion(
            in: [completed],
            deviceStatus: .offline,
            deviceLastUpdate: Date.now
        )

        #expect(result[0].endTime == completed.endTime)
    }

    @Test("Only the newest excursion is a candidate, older completed ones are untouched")
    func onlyClosesTheNewestExcursion() {
        let older = excursion(id: 1, startSecondsAgo: 10_000, endSecondsAgo: 9_000)
        let newest = excursion(id: 2, startSecondsAgo: 3_600, endSecondsAgo: nil)
        let lastUpdate = Date.now.addingTimeInterval(-1_800)

        let result = TraccarPetRepository.closingAbandonedExcursion(
            in: [older, newest],
            deviceStatus: .offline,
            deviceLastUpdate: lastUpdate
        )

        let resultByID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(resultByID[1]?.endTime == older.endTime)
        #expect(resultByID[2]?.endTime == lastUpdate)
    }

    @Test("An empty excursion list is returned unchanged")
    func handlesEmptyList() {
        let result = TraccarPetRepository.closingAbandonedExcursion(in: [], deviceStatus: .offline, deviceLastUpdate: Date.now)
        #expect(result.isEmpty)
    }
}
