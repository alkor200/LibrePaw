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

    /// The pet's configured home area, if any (see ADR-0014). `nil` when no
    /// home has been set yet.
    func homeGeofence(forPetID petID: Int) async throws -> HomeGeofence?

    /// Sets (or moves) the pet's home area. Creates it on first use, or
    /// updates the existing one in place.
    func setHomeGeofence(forPetID petID: Int, center: Coordinate, radiusMeters: Double) async throws

    /// Excursions — trips away from home and back — within a time range,
    /// most recent first. Requires a home geofence to already be set;
    /// returns an empty array otherwise.
    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion]

    /// Total distance and time away across every excursion the pet has ever
    /// taken. Implementations are expected to cache completed excursions'
    /// contributions so this doesn't re-walk the pet's whole history on
    /// every call — only an ongoing excursion (if any) is recomputed fresh.
    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats
}
