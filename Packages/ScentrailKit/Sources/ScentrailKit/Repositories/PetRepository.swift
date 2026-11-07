import Foundation

/// Reads pets and their positions for the currently authenticated session.
public protocol PetRepository: Sendable {
    /// All pets visible to the current user, each with its latest known
    /// position attached (if the tracker has ever reported one).
    func fetchPets() async throws -> [Pet]

    /// The position history for one pet within a time range, oldest first —
    /// used to draw a recent trail on the map.
    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition]

    /// The pet's photo bytes, fetched with the same credentials as every
    /// other request (Traccar's device media endpoint requires auth). `nil`
    /// when the pet has no photo set.
    func fetchPhoto(for pet: Pet) async throws -> Data?

    /// A continuous stream of the full, current pet list: one initial
    /// snapshot, then a fresh snapshot each time Traccar's live feed reports
    /// a changed device or position (see ADR-0013). Finishes only on an
    /// unrecoverable error or when the caller stops consuming it.
    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error>
}
