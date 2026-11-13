import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("TrailViewModel.loadTrails")
struct TrailViewModelTests {
    private let now = Date.now

    private func excursion(id: Int) -> Excursion {
        Excursion(id: id, startTime: start(of: id), endTime: now, startCoordinate: nil, endCoordinate: nil, distanceMeters: nil)
    }

    private func start(of id: Int) -> Date {
        now.addingTimeInterval(-3_600 * Double(id))
    }

    @Test("One failed route is left out instead of failing every other one")
    func oneFailureDoesNotFailAll() async throws {
        let repository = FakePetRepository(failingTrailStarts: [start(of: 2)])

        let trails = try await TrailViewModel.loadTrails(for: [excursion(id: 1), excursion(id: 2), excursion(id: 3)], petID: 1, petRepository: repository)

        #expect(Set(trails.keys) == [1, 3])
    }

    @Test("When every route fails, the error surfaces")
    func allFailuresThrow() async {
        let repository = FakePetRepository(failingTrailStarts: [start(of: 1), start(of: 2)])

        await #expect(throws: LibrePawError.self) {
            try await TrailViewModel.loadTrails(for: [excursion(id: 1), excursion(id: 2)], petID: 1, petRepository: repository)
        }
    }
}
