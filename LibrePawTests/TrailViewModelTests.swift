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

@Suite("TrailViewModel.interval")
@MainActor
struct TrailIntervalTests {
    private let pet = Pet(id: 1, name: "Buddy", species: nil, status: .online, lastSeenAt: nil, lastPosition: nil)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test("A preset reaches back from now")
    func presetReachesBackFromNow() {
        let viewModel = TrailViewModel(pet: pet, petRepository: FakePetRepository())
        viewModel.window = .sevenDays
        let now = date(20)

        let interval = viewModel.interval(now: now, calendar: calendar)

        #expect(interval.from == now.addingTimeInterval(-7 * 86_400))
        #expect(interval.to == now)
    }

    @Test("A custom range covers its first and last day entirely")
    func customRangeCoversWholeDays() {
        let viewModel = TrailViewModel(pet: pet, petRepository: FakePetRepository())
        viewModel.window = .custom
        viewModel.customRange = date(10, 15)...date(12, 9)

        let interval = viewModel.interval(now: date(20), calendar: calendar)

        #expect(interval.from == date(10, 0))
        #expect(interval.to == date(13, 0))
    }

    @Test("A custom range ending today stops at now")
    func customRangeEndingTodayStopsAtNow() {
        let viewModel = TrailViewModel(pet: pet, petRepository: FakePetRepository())
        viewModel.window = .custom
        viewModel.customRange = date(15)...date(20)
        let now = date(20, 14)

        #expect(viewModel.interval(now: now, calendar: calendar).to == now)
    }
}
