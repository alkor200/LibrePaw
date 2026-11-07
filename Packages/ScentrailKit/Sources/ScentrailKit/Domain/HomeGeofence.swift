import Foundation

/// A pet's "home" area, used to detect excursions (see ADR-0014). Set from
/// the owner's current location plus a radius — never drawn by hand on a
/// map, to keep the setup flow to a single tap.
public struct HomeGeofence: Sendable, Equatable {
    public let center: Coordinate
    public let radiusMeters: Double

    public init(center: Coordinate, radiusMeters: Double) {
        self.center = center
        self.radiusMeters = radiusMeters
    }
}
