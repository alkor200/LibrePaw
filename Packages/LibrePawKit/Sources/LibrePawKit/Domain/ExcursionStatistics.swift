import Foundation

/// Everything the Statistics screen shows about a pet's walks, computed
/// from its excursions over a range of days.
///
/// Walks are closed excursions that weren't likely vehicle trips (see
/// ``Excursion/isLikelyVehicleTrip``), the same ones the lifetime totals
/// count. An excursion still ongoing counts toward its day's and the
/// overall totals with what's known so far, but not toward distributions
/// or records, it isn't finished yet. Every day of the range is present in
/// ``days``, days without a walk included, so averages and the calendar
/// reflect them.
public struct ExcursionStatistics: Sendable {
    public struct Day: Sendable, Hashable, Identifiable {
        /// Start of the day.
        public let date: Date
        public let distanceMeters: Double
        public let durationSeconds: TimeInterval
        public let walkCount: Int
        public var id: Date { date }
    }

    public struct Week: Sendable, Hashable, Identifiable {
        /// Start of the week.
        public let date: Date
        public let distanceMeters: Double
        public let durationSeconds: TimeInterval
        public let walkCount: Int
        /// How many of its days lie in the range, fewer than 7 for the
        /// range's first and current week.
        public let dayCount: Int
        public var id: Date { date }

        /// Comparable between full and partial weeks, unlike the total.
        public var averageDistancePerDay: Double { dayCount > 0 ? distanceMeters / Double(dayCount) : 0 }
    }

    public struct WeekdayAverage: Sendable, Hashable, Identifiable {
        /// `Calendar` weekday, 1 is Sunday.
        public let weekday: Int
        /// Averaged over every occurrence of this weekday in the range.
        public let distanceMeters: Double
        public let durationSeconds: TimeInterval
        public let walksPerDay: Double
        public var id: Int { weekday }
    }

    public struct Bucket: Sendable, Hashable, Identifiable {
        public let lowerBound: Double
        /// `nil` for the open-ended last bucket.
        public let upperBound: Double?
        public let count: Int
        public var id: Double { lowerBound }
    }

    /// Closed walks in the range, oldest first.
    public let walks: [Excursion]
    /// The excursion still going on, if any.
    public let ongoing: Excursion?
    /// Every day of the range, oldest first.
    public let days: [Day]
    /// Every week of the range, oldest first, as weeks start in `calendar`.
    public let weeks: [Week]
    /// One per weekday, in the calendar's own order (Monday first in
    /// Germany).
    public let weekdays: [WeekdayAverage]
    /// How many walks started in each hour of the day, 24 entries.
    public let startHours: [Int]
    /// In seconds.
    public let durationBuckets: [Bucket]
    /// In meters.
    public let distanceBuckets: [Bucket]
    /// Excursions in the range left out as likely vehicle trips.
    public let vehicleTripCount: Int
    /// Walks in the range that ended with the tracker losing its signal,
    /// their distance and duration are only what was recorded.
    public let lostSignalCount: Int

    public static let durationBucketBounds: [TimeInterval] = [0, 15, 30, 45, 60, 90].map { $0 * 60 }
    public static let distanceBucketBounds: [Double] = [0, 500, 1_000, 2_000, 3_000, 5_000]
    /// Shorter walks are left out of "fastest", a few minutes of trotting
    /// says little about a pet's pace.
    public static let minimumDurationForSpeedRecord: TimeInterval = 10 * 60

    /// - Parameter from: the first day of the range, `nil` for "since the
    ///   first walk on record".
    public init(excursions: [Excursion], from: Date?, now: Date = .now, calendar: Calendar = .current) {
        let rangeStart = from.map { calendar.startOfDay(for: $0) }
        let inRange = excursions
            .filter { rangeStart == nil || $0.startTime >= rangeStart! }
            .filter { $0.startTime <= now }
            .sorted { $0.startTime < $1.startTime }

        vehicleTripCount = inRange.filter { $0.endTime != nil && $0.isLikelyVehicleTrip }.count
        let counted = inRange.filter { !$0.isLikelyVehicleTrip }
        walks = counted.filter { $0.endTime != nil }
        ongoing = counted.last { $0.isOngoing }
        lostSignalCount = walks.filter(\.endedWithLostSignal).count

        // Days
        let today = calendar.startOfDay(for: now)
        let firstDay = rangeStart ?? counted.first.map { calendar.startOfDay(for: $0.startTime) } ?? today
        var totalsByDay: [Date: (distance: Double, duration: TimeInterval, count: Int)] = [:]
        for excursion in counted {
            let day = calendar.startOfDay(for: excursion.startTime)
            let duration = excursion.duration ?? now.timeIntervalSince(excursion.startTime)
            var entry = totalsByDay[day] ?? (0, 0, 0)
            entry.distance += excursion.distanceMeters ?? 0
            entry.duration += duration
            entry.count += 1
            totalsByDay[day] = entry
        }
        var days: [Day] = []
        var day = firstDay
        while day <= today {
            let entry = totalsByDay[day] ?? (0, 0, 0)
            days.append(Day(date: day, distanceMeters: entry.distance, durationSeconds: entry.duration, walkCount: entry.count))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        self.days = days

        // Weeks
        var weekOrder: [Date] = []
        var totalsByWeek: [Date: (distance: Double, duration: TimeInterval, count: Int, days: Int)] = [:]
        for day in days {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: day.date)?.start else { continue }
            if totalsByWeek[week] == nil { weekOrder.append(week) }
            var entry = totalsByWeek[week] ?? (0, 0, 0, 0)
            entry.distance += day.distanceMeters
            entry.duration += day.durationSeconds
            entry.count += day.walkCount
            entry.days += 1
            totalsByWeek[week] = entry
        }
        weeks = weekOrder.map { week in
            let entry = totalsByWeek[week]!
            return Week(date: week, distanceMeters: entry.distance, durationSeconds: entry.duration, walkCount: entry.count, dayCount: entry.days)
        }

        // Weekdays, in the calendar's own order
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        weekdays = order.map { weekday in
            let matching = days.filter { calendar.component(.weekday, from: $0.date) == weekday }
            let count = Double(max(matching.count, 1))
            return WeekdayAverage(
                weekday: weekday,
                distanceMeters: matching.reduce(0) { $0 + $1.distanceMeters } / count,
                durationSeconds: matching.reduce(0) { $0 + $1.durationSeconds } / count,
                walksPerDay: Double(matching.reduce(0) { $0 + $1.walkCount }) / count
            )
        }

        // Distributions
        var hours = Array(repeating: 0, count: 24)
        for walk in walks {
            hours[calendar.component(.hour, from: walk.startTime)] += 1
        }
        startHours = hours
        durationBuckets = Self.buckets(walks.compactMap(\.duration), bounds: Self.durationBucketBounds)
        distanceBuckets = Self.buckets(walks.compactMap(\.distanceMeters), bounds: Self.distanceBucketBounds)
    }

    private static func buckets(_ values: [Double], bounds: [Double]) -> [Bucket] {
        bounds.enumerated().map { index, lower in
            let upper = index + 1 < bounds.count ? bounds[index + 1] : nil
            let count = values.filter { $0 >= lower && (upper == nil || $0 < upper!) }.count
            return Bucket(lowerBound: lower, upperBound: upper, count: count)
        }
    }

    // MARK: - Totals and averages

    public var totalDistanceMeters: Double { days.reduce(0) { $0 + $1.distanceMeters } }
    public var totalDurationSeconds: TimeInterval { days.reduce(0) { $0 + $1.durationSeconds } }
    public var walkCount: Int { walks.count }
    public var dayCount: Int { days.count }

    public var averageDistancePerDay: Double { dayCount > 0 ? totalDistanceMeters / Double(dayCount) : 0 }
    public var averageDurationPerDay: TimeInterval { dayCount > 0 ? totalDurationSeconds / Double(dayCount) : 0 }
    public var averageWalksPerDay: Double { dayCount > 0 ? Double(days.reduce(0) { $0 + $1.walkCount }) / Double(dayCount) : 0 }

    public var averageDistancePerWalk: Double? {
        walks.isEmpty ? nil : walks.reduce(0) { $0 + ($1.distanceMeters ?? 0) } / Double(walks.count)
    }

    public var averageDurationPerWalk: TimeInterval? {
        walks.isEmpty ? nil : walks.reduce(0) { $0 + ($1.duration ?? 0) } / Double(walks.count)
    }

    /// Over every closed walk together, not an average of averages.
    public var averageSpeedKilometersPerHour: Double? {
        let distance = walks.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
        let duration = walks.reduce(0) { $0 + ($1.duration ?? 0) }
        return duration > 0 ? distance / duration * 3.6 : nil
    }

    // MARK: - Records

    public var farthestWalk: Excursion? { walks.max { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) } }
    public var longestWalk: Excursion? { walks.max { ($0.duration ?? 0) < ($1.duration ?? 0) } }

    public var fastestWalk: Excursion? {
        walks
            .filter { ($0.duration ?? 0) >= Self.minimumDurationForSpeedRecord }
            .max { ($0.averageSpeedKilometersPerHour ?? 0) < ($1.averageSpeedKilometersPerHour ?? 0) }
    }

    public var mostActiveDay: Day? {
        days.filter { $0.distanceMeters > 0 }.max { $0.distanceMeters < $1.distanceMeters }
    }

    /// Consecutive days with at least one walk, up to today, or up to
    /// yesterday while today has none yet.
    public var currentStreak: Int {
        var remaining = days[...]
        if let last = remaining.last, last.walkCount == 0 { remaining = remaining.dropLast() }
        return remaining.reversed().prefix { $0.walkCount > 0 }.count
    }

    public var longestStreak: Int {
        var longest = 0
        var current = 0
        for day in days {
            current = day.walkCount > 0 ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    /// Where a "day" starts for ``earliestStartingWalk(calendar:)`` and
    /// ``latestStartingWalk(calendar:)``: a walk at 1:17 at night is a
    /// very late one, not the earliest of the day.
    public static let dayBoundaryHour = 4

    /// The walk that started earliest in the day, by time of day.
    public func earliestStartingWalk(calendar: Calendar = .current) -> Excursion? {
        walks.min { Self.minuteOfDay($0.startTime, calendar) < Self.minuteOfDay($1.startTime, calendar) }
    }

    /// The walk that started latest in the day, by time of day.
    public func latestStartingWalk(calendar: Calendar = .current) -> Excursion? {
        walks.max { Self.minuteOfDay($0.startTime, calendar) < Self.minuteOfDay($1.startTime, calendar) }
    }

    private static func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return (minute - dayBoundaryHour * 60 + 24 * 60) % (24 * 60)
    }
}
