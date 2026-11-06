import Foundation

/// A tracked pet, as understood by Scentrail.
///
/// This is Scentrail's own domain model, mapped from a Traccar "device" at
/// the repository boundary (see ADR-0002 and ADR-0005) — nothing above
/// ``PetRepository`` needs to know that Traccar, or the word "device",
/// exists.
public struct Pet: Identifiable, Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        case online
        case offline
        case unknown
    }

    public let id: Int
    public let name: String
    /// Free-form species/category (e.g. "dog", "cat"), if the owner set one
    /// on the Traccar device. `nil` when not configured.
    public let species: String?
    public let status: Status
    public let lastSeenAt: Date?
    public let lastPosition: PetPosition?

    public init(
        id: Int,
        name: String,
        species: String?,
        status: Status,
        lastSeenAt: Date?,
        lastPosition: PetPosition?
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.status = status
        self.lastSeenAt = lastSeenAt
        self.lastPosition = lastPosition
    }
}
