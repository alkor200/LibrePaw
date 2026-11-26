import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("StatsViewModel")
@MainActor
struct StatsViewModelTests {
    private let pet = Pet(id: 1, name: "Buddy", species: nil, status: .online, lastSeenAt: nil, lastPosition: nil)

    private func walk(_ id: Int, daysAgo: Int, minutes: Double, meters: Double) -> Excursion {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: .now))!.addingTimeInterval(9 * 3_600)
        return Excursion(id: id, startTime: start, endTime: start.addingTimeInterval(minutes * 60), startCoordinate: nil, endCoordinate: nil, distanceMeters: meters)
    }

    @Test("Loads every excursion and narrows the statistics to the chosen range")
    func rangeNarrowsStatistics() async {
        let repository = FakePetRepository(excursions: [
            walk(1, daysAgo: 40, minutes: 30, meters: 2_000),
            walk(2, daysAgo: 3, minutes: 45, meters: 3_000),
            walk(3, daysAgo: 1, minutes: 20, meters: 1_000)
        ])
        let viewModel = StatsViewModel(pet: pet, petRepository: repository)

        await viewModel.load()
        #expect(viewModel.statistics?.walkCount == 3)

        viewModel.range = .week
        #expect(viewModel.statistics?.walkCount == 2)
        #expect(viewModel.statistics?.dayCount == 7)
    }

    @Test("A failed recalculation is reported instead of swallowed")
    func failedRecalculationIsReported() async {
        let viewModel = StatsViewModel(pet: pet, petRepository: FakePetRepository(excursionsError: LibrePawError.network("offline")))

        await viewModel.recalculate()

        #expect(viewModel.recalculateErrorMessage != nil)
    }
}
