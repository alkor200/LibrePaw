import Foundation
import Testing
@testable import LibrePawKit

@Suite("ExcursionStatistics")
struct ExcursionStatisticsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func walk(_ id: Int, day: Int, hour: Int, minutes: Double, meters: Double, lostSignal: Bool = false) -> Excursion {
        let start = date(day, hour)
        return Excursion(id: id, startTime: start, endTime: start.addingTimeInterval(minutes * 60), startCoordinate: nil,
                         endCoordinate: nil, distanceMeters: meters, endedWithLostSignal: lostSignal)
    }

    // Mon 16 to Sun 22 November 2026, "now" Sunday evening.
    private var week: [Excursion] {
        [
            walk(1, day: 16, hour: 8, minutes: 30, meters: 1_500),
            walk(2, day: 16, hour: 18, minutes: 60, meters: 3_000),
            walk(3, day: 17, hour: 7, minutes: 20, meters: 1_000),
            // Wednesday 18: nothing.
            walk(4, day: 19, hour: 21, minutes: 45, meters: 2_500, lostSignal: true),
            walk(5, day: 20, hour: 12, minutes: 10, meters: 200),
            walk(6, day: 21, hour: 9, minutes: 30, meters: 20_000), // 40 km/h, a car ride
            walk(7, day: 22, hour: 10, minutes: 90, meters: 6_000)
        ]
    }

    private var stats: ExcursionStatistics {
        ExcursionStatistics(excursions: week, from: date(16, 0), now: date(22, 20), calendar: calendar)
    }

    @Test("Every day of the range is there, walkless ones included, car rides left out")
    func days() {
        #expect(stats.dayCount == 7)
        #expect(stats.days.map(\.walkCount) == [2, 1, 0, 1, 1, 0, 1])
        #expect(stats.days[0].distanceMeters == 4_500)
        #expect(stats.vehicleTripCount == 1)
        #expect(stats.walkCount == 6)
        #expect(stats.lostSignalCount == 1)
    }

    @Test("Totals and averages")
    func totalsAndAverages() throws {
        #expect(stats.totalDistanceMeters == 14_200)
        #expect(stats.totalDurationSeconds == 255 * 60)
        #expect(abs(stats.averageDistancePerDay - 14_200 / 7) < 0.001)
        #expect(abs(try #require(stats.averageDistancePerWalk) - 14_200 / 6) < 0.001)
        #expect(abs(try #require(stats.averageSpeedKilometersPerHour) - 14.2 / (255.0 / 60)) < 0.001)
    }

    @Test("Records, ignoring walks too short for a speed record")
    func records() {
        #expect(stats.farthestWalk?.id == 7)
        #expect(stats.longestWalk?.id == 7)
        // Walk 5 is 1.2 km/h but only 10 minutes, still counts; walk 2 and 7 are 3 and 4 km/h.
        #expect(stats.fastestWalk?.id == 7)
        #expect(stats.mostActiveDay?.date == date(22, 0))
        #expect(stats.earliestStartingWalk(calendar: calendar)?.id == 3)
        #expect(stats.latestStartingWalk(calendar: calendar)?.id == 4)
    }

    @Test("A walk after midnight counts as the latest of the day, not the earliest")
    func nightWalkIsLatest() {
        let night = walk(8, day: 18, hour: 1, minutes: 15, meters: 500)
        let stats = ExcursionStatistics(excursions: week + [night], from: date(16, 0), now: date(22, 20), calendar: calendar)

        #expect(stats.earliestStartingWalk(calendar: calendar)?.id == 3)
        #expect(stats.latestStartingWalk(calendar: calendar)?.id == 8)
    }

    @Test("Weeks know how many of their days are in the range")
    func partialWeeks() {
        let stats = ExcursionStatistics(excursions: week, from: date(19, 0), now: date(24, 20), calendar: calendar)

        #expect(stats.weeks.map(\.dayCount) == [4, 2])
        #expect(stats.weeks[1].averageDistancePerDay == 0)
    }

    @Test("Streaks count consecutive days with a walk")
    func streaks() {
        // Thu 19, Fri 20 walked, Sat 21 only a car ride, Sun 22 walked.
        #expect(stats.currentStreak == 1)
        #expect(stats.longestStreak == 2)
    }

    @Test("Weekdays follow the calendar's own order, start hours and buckets count every walk")
    func distributions() {
        #expect(stats.weekdays.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
        #expect(stats.weekdays[0].distanceMeters == 4_500)
        #expect(stats.startHours.reduce(0, +) == 6)
        #expect(stats.startHours[8] == 1)
        #expect(stats.durationBuckets.reduce(0) { $0 + $1.count } == 6)
        #expect(stats.distanceBuckets.last?.upperBound == nil)
        #expect(stats.distanceBuckets.last?.count == 1)
    }

    @Test("An ongoing walk counts toward today's totals but not toward walks and records")
    func ongoingWalk() {
        let ongoing = Excursion(id: 9, startTime: date(22, 19), endTime: nil, startCoordinate: nil, endCoordinate: nil, distanceMeters: 800)
        let stats = ExcursionStatistics(excursions: week + [ongoing], from: date(16, 0), now: date(22, 20), calendar: calendar)

        #expect(stats.ongoing?.id == 9)
        #expect(stats.walkCount == 6)
        #expect(stats.days.last?.walkCount == 2)
        let lastDuration = stats.days.last?.durationSeconds ?? -1
        #expect(lastDuration == 150 * 60, "got \(lastDuration / 60) min")
    }

    @Test("Without a range start, the range begins with the first walk")
    func openRange() {
        let stats = ExcursionStatistics(excursions: week, from: nil, now: date(22, 20), calendar: calendar)
        #expect(stats.days.first?.date == date(16, 0))
    }
}
