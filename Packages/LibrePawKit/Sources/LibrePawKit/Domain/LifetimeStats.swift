import Foundation

/// A pet's totals across every excursion it has ever taken, not just the
/// ones currently loaded on the Excursions screen.
public struct LifetimeStats: Sendable, Equatable {
    public let totalDistanceMeters: Double
    public let totalDurationSeconds: TimeInterval
    /// When the earliest excursion counted in the totals started, `nil`
    /// while there is none. What ``dailyAverages(asOf:calendar:)`` counts
    /// days from.
    public let firstExcursionStartTime: Date?

    public init(totalDistanceMeters: Double, totalDurationSeconds: TimeInterval, firstExcursionStartTime: Date? = nil) {
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.firstExcursionStartTime = firstExcursionStartTime
    }

    public static let zero = LifetimeStats(totalDistanceMeters: 0, totalDurationSeconds: 0)

    /// The totals spread over every calendar day from the first excursion's
    /// day through `date`'s, both included, so days without a walk pull the
    /// average down the way they should. `nil` without any excursion yet.
    public func dailyAverages(asOf date: Date = .now, calendar: Calendar = .current) -> (distanceMeters: Double, durationSeconds: TimeInterval)? {
        guard let firstExcursionStartTime else { return nil }
        let days = (calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: firstExcursionStartTime),
            to: calendar.startOfDay(for: date)
        ).day ?? 0) + 1
        guard days > 0 else { return nil }
        return (totalDistanceMeters / Double(days), totalDurationSeconds / Double(days))
    }
}
