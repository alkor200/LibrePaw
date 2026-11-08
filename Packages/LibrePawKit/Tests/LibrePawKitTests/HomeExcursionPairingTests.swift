import Foundation
import Testing
import TraccarKit
@testable import LibrePawKit

@Suite("TraccarPetRepository.pairHomeExitsWithEnters")
struct HomeExcursionPairingTests {
    private func event(id: Int, type: String, secondsFromNow: TimeInterval, geofenceId: Int?) -> TraccarEvent {
        TraccarEvent(id: id, type: type, eventTime: Date.now.addingTimeInterval(secondsFromNow), deviceId: 1, geofenceId: geofenceId)
    }

    @Test("A pet leaving one home and returning via another pairs as a single excursion")
    func exitAndEnterAtDifferentHomesStillPair() {
        // Home 1 ("Home") exit, Home 2 ("Cabin") enter, a trip between the
        // two, not a round trip to either one (see ADR-0016).
        let exit = event(id: 1, type: TraccarEvent.EventType.geofenceExit, secondsFromNow: -3_600, geofenceId: 1)
        let enter = event(id: 2, type: TraccarEvent.EventType.geofenceEnter, secondsFromNow: -1_800, geofenceId: 2)

        let pairs = TraccarPetRepository.pairHomeExitsWithEnters(exits: [exit], enters: [enter])

        #expect(pairs.count == 1)
        #expect(pairs[0].exit.geofenceId == 1)
        #expect(pairs[0].enter?.geofenceId == 2)
    }

    @Test("Exits and enters across several homes are merged purely by time, not grouped per geofence")
    func mergesAcrossHomesChronologically() {
        // Leaves Home 1, passes near Home 2 without stopping long enough to
        // register, then returns to Home 1, one excursion, using only the
        // first exit and the next enter after it.
        let exitHome1 = event(id: 1, type: TraccarEvent.EventType.geofenceExit, secondsFromNow: -7_200, geofenceId: 1)
        let enterHome1 = event(id: 2, type: TraccarEvent.EventType.geofenceEnter, secondsFromNow: -3_600, geofenceId: 1)

        let pairs = TraccarPetRepository.pairHomeExitsWithEnters(exits: [exitHome1], enters: [enterHome1])

        #expect(pairs.count == 1)
        #expect(pairs[0].enter?.id == 2)
    }

    @Test("An exit with no following enter yet is ongoing")
    func exitWithoutLaterEnterIsOngoing() {
        let exit = event(id: 1, type: TraccarEvent.EventType.geofenceExit, secondsFromNow: -600, geofenceId: 1)

        let pairs = TraccarPetRepository.pairHomeExitsWithEnters(exits: [exit], enters: [])

        #expect(pairs.count == 1)
        #expect(pairs[0].enter == nil)
    }

    @Test("Each enter is consumed at most once, even with multiple homes in play")
    func eachEnterIsConsumedOnce() {
        let firstExit = event(id: 1, type: TraccarEvent.EventType.geofenceExit, secondsFromNow: -10_000, geofenceId: 1)
        let firstEnter = event(id: 2, type: TraccarEvent.EventType.geofenceEnter, secondsFromNow: -9_000, geofenceId: 2)
        let secondExit = event(id: 3, type: TraccarEvent.EventType.geofenceExit, secondsFromNow: -5_000, geofenceId: 2)
        let secondEnter = event(id: 4, type: TraccarEvent.EventType.geofenceEnter, secondsFromNow: -4_000, geofenceId: 1)

        let pairs = TraccarPetRepository.pairHomeExitsWithEnters(
            exits: [firstExit, secondExit],
            enters: [firstEnter, secondEnter]
        )

        #expect(pairs.count == 2)
        #expect(pairs[0].enter?.id == 2)
        #expect(pairs[1].enter?.id == 4)
    }
}
