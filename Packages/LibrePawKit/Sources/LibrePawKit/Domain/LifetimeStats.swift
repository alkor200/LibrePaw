import Foundation

/// A pet's totals across every excursion it has ever taken, not just the
/// ones currently loaded on the Excursions screen.
public struct LifetimeStats: Sendable, Equatable {
    public let totalDistanceMeters: Double
    public let totalDurationSeconds: TimeInterval

    public init(totalDistanceMeters: Double, totalDurationSeconds: TimeInterval) {
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
    }

    public static let zero = LifetimeStats(totalDistanceMeters: 0, totalDurationSeconds: 0)
}
