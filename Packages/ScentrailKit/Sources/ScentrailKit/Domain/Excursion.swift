import Foundation

/// One trip away from home and back, derived from home-geofence exit/enter
/// events rather than Traccar's generic motion-based trip detection — see
/// ADR-0014 for why (the generic one is far too sensitive to a pet's
/// movement pattern to be useful).
public struct Excursion: Identifiable, Sendable, Hashable {
    public let id: Int
    public let startTime: Date
    /// `nil` while the pet is still away — the excursion is ongoing.
    public let endTime: Date?
    public let startCoordinate: Coordinate?
    public let endCoordinate: Coordinate?
    /// Total distance covered along the recorded trail, `nil` if too few
    /// positions were reported to measure it.
    public let distanceMeters: Double?

    public init(
        id: Int,
        startTime: Date,
        endTime: Date?,
        startCoordinate: Coordinate?,
        endCoordinate: Coordinate?,
        distanceMeters: Double?
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.startCoordinate = startCoordinate
        self.endCoordinate = endCoordinate
        self.distanceMeters = distanceMeters
    }

    public var isOngoing: Bool { endTime == nil }

    public var duration: TimeInterval? {
        guard let endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    public var averageSpeedKilometersPerHour: Double? {
        guard let distanceMeters, let duration, duration > 0 else { return nil }
        return (distanceMeters / duration) * 3.6
    }

    /// A pet walking — even sprinting after a ball, with sniff-stops
    /// averaged in — essentially never sustains more than this across an
    /// entire excursion. Above it, "home to home" almost certainly means a
    /// car or train ride, not a walk, which would otherwise badly skew
    /// distance/time-away stats. Purely a heuristic on data already fetched
    /// for every excursion (no extra requests, no server configuration).
    private static let vehicleSpeedThresholdKilometersPerHour = 15.0

    /// `false` while ongoing — there's no average speed to judge yet.
    public var isLikelyVehicleTrip: Bool {
        guard let averageSpeedKilometersPerHour else { return false }
        return averageSpeedKilometersPerHour > Self.vehicleSpeedThresholdKilometersPerHour
    }
}
