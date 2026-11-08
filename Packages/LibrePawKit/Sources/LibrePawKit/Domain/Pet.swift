import Foundation

/// A tracked pet, as understood by LibrePaw.
///
/// This is LibrePaw's own domain model, mapped from a Traccar "device" at
/// the repository boundary (see ADR-0002 and ADR-0005), nothing above
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
    /// A photo of the pet, read from the Traccar device's `photo` attribute
    /// (see ADR-0011). `nil` when the owner hasn't set one.
    public let photoURL: URL?

    public init(
        id: Int,
        name: String,
        species: String?,
        status: Status,
        lastSeenAt: Date?,
        lastPosition: PetPosition?,
        photoURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.status = status
        self.lastSeenAt = lastSeenAt
        self.lastPosition = lastPosition
        self.photoURL = photoURL
    }
}
