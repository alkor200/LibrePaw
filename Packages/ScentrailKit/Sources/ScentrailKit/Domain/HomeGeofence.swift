import Foundation

/// One of a pet's "home" areas, used to detect excursions (see ADR-0014). A
/// pet can have several (ADR-0016) - e.g. a primary residence and a cabin -
/// each set from the owner's current location plus a radius, never drawn by
/// hand on a map, to keep the setup flow to a single tap.
public struct HomeGeofence: Sendable, Hashable, Identifiable {
    /// The underlying Traccar geofence id - stable across renames/moves, so
    /// it's what callers use to update or delete a specific home.
    public let id: Int
    public let name: String
    public let center: Coordinate
    public let radiusMeters: Double

    public init(id: Int, name: String, center: Coordinate, radiusMeters: Double) {
        self.id = id
        self.name = name
        self.center = center
        self.radiusMeters = radiusMeters
    }
}
