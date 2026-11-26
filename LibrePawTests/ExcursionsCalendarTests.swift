import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("ExcursionsViewModel calendar")
@MainActor
struct ExcursionsCalendarTests {
    private let pet = Pet(id: 1, name: "Buddy", species: nil, status: .online, lastSeenAt: nil, lastPosition: nil)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func walk(_ id: Int, from start: Date, minutes: Double, meters: Double) -> Excursion {
        Excursion(id: id, startTime: start, endTime: start.addingTimeInterval(minutes * 60), startCoordinate: nil, endCoordinate: nil, distanceMeters: meters)
    }

    private func makeViewModel(_ excursions: [Excursion] = []) async -> ExcursionsViewModel {
        let viewModel = ExcursionsViewModel(pet: pet, petRepository: FakePetRepository(excursions: excursions), now: date(26, 12), calendar: calendar)
        await viewModel.load()
        return viewModel
    }

    @Test("Steps by month, week or day depending on the mode")
    func stepping() async {
        let viewModel = await makeViewModel()

        viewModel.step(1)
        #expect(viewModel.anchor == date(26, month: 12))
        viewModel.mode = .week
        viewModel.step(-1)
        #expect(viewModel.anchor == date(19, month: 12))
        viewModel.mode = .day
        viewModel.step(-1)
        #expect(viewModel.anchor == date(18, month: 12))
    }

    @Test("The month grid starts on the calendar's first weekday and pads both ends")
    func monthGrid() async {
        let viewModel = await makeViewModel()
        let grid = viewModel.monthGrid

        // November 2026 starts on a Sunday: six empty slots first in a Monday-first week.
        #expect(grid.first?.prefix(6).allSatisfy { $0 == nil } == true)
        #expect(grid.first?[6] == date(1))
        #expect(grid.allSatisfy { $0.count == 7 })
        #expect(grid.flatMap { $0 }.compactMap { $0 }.count == 30)
    }

    @Test("A walk past midnight shows on both days, clipped to each, but counts on the day it started")
    func walkPastMidnight() async throws {
        let late = walk(1, from: date(20, 23, 30), minutes: 60, meters: 2_000)
        let viewModel = await makeViewModel([late])

        #expect(viewModel.excursions(on: date(20)).map(\.id) == [1])
        #expect(viewModel.excursions(on: date(21)).map(\.id) == [1])
        let firstDay = try #require(viewModel.dayFractions(of: late, on: date(20)))
        #expect(abs(firstDay.lowerBound - 23.5 / 24) < 0.0001)
        #expect(firstDay.upperBound == 1)
        let secondDay = try #require(viewModel.dayFractions(of: late, on: date(21)))
        #expect(secondDay.lowerBound == 0)
        #expect(abs(secondDay.upperBound - 0.5 / 24) < 0.0001)

        #expect(viewModel.totals(on: date(20)).walkCount == 1)
        #expect(viewModel.totals(on: date(21)).walkCount == 0)
    }

    @Test("Totals leave car rides out, week totals cover the shown week only")
    func totals() async {
        let viewModel = await makeViewModel([
            walk(1, from: date(23, 8), minutes: 30, meters: 1_500),
            walk(2, from: date(24, 9), minutes: 30, meters: 20_000), // 40 km/h
            walk(3, from: date(16, 8), minutes: 30, meters: 1_000)  // the week before
        ])
        viewModel.mode = .week

        let totals = viewModel.shownTotals(now: date(26, 12))
        #expect(totals.walkCount == 1)
        #expect(totals.distanceMeters == 1_500)
        #expect(viewModel.shownDays.first == date(23))
        #expect(viewModel.shownDays.count == 7)
    }

    @Test("A tapped day opens as its own day screen with the excursions already loaded")
    func openedDay() async {
        let viewModel = await makeViewModel([walk(1, from: date(3, 8), minutes: 30, meters: 1_500)])
        let day = viewModel.viewModel(forOpenedDay: date(3, 15))

        #expect(day.isOpenedDay)
        #expect(day.mode == .day)
        #expect(day.anchor == date(3))
        #expect(!day.isLoading)
        #expect(day.excursions(on: date(3)).map(\.id) == [1])
        #expect(viewModel.mode == .month)
    }
}
