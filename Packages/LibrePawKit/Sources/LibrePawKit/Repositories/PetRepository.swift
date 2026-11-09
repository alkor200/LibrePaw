import Foundation

/// Reads pets and their positions for the currently authenticated session.
public protocol PetRepository: Sendable {
    /// All pets visible to the current user, each with its latest known
    /// position attached (if the tracker has ever reported one).
    func fetchPets() async throws -> [Pet]

    /// The position history for one pet within a time range, oldest first -
    /// used to draw a recent trail on the map.
    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition]

    /// The pet's photo bytes, fetched with the same credentials as every
    /// other request (Traccar's device media endpoint requires auth). `nil`
    /// when the pet has no photo set.
    func fetchPhoto(for pet: Pet) async throws -> Data?

    /// Sets (or replaces) the pet's photo. `jpegData` must already be
    /// JPEG-encoded and under Traccar's upload size limit (500KB).
    func setPhoto(forPetID petID: Int, jpegData: Data) async throws

    /// Renames the pet, i.e. its underlying Traccar device. `name` is used
    /// as-is, callers are expected to have already trimmed/validated it.
    func renamePet(forPetID petID: Int, name: String) async throws

    /// A continuous stream of the full, current pet list: one initial
    /// snapshot, then a fresh snapshot each time Traccar's live feed reports
    /// a changed device or position (see ADR-0013). Finishes only on an
    /// unrecoverable error or when the caller stops consuming it.
    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error>

    /// The pet's configured home areas (see ADR-0014, ADR-0016), empty when
    /// none has been set yet, or when the current user has permission to see
    /// the pet but not (yet) this particular home, see ADR-0017.
    func homeGeofences(forPetID petID: Int) async throws -> [HomeGeofence]

    /// Adds a new home area, linked to the pet's device and, best-effort -
    /// to every user who can already see that device, so a home one
    /// household member sets up is visible to the rest too (see ADR-0017).
    func addHomeGeofence(forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws

    /// Moves and/or renames an existing home area in place, same geofence
    /// id, so nothing else needs to be redone (its device link, any
    /// in-flight excursion that references it). Also re-syncs which users
    /// can see it, the same way ``addHomeGeofence(forPetID:name:center:radiusMeters:)``
    /// does, editing a home is the repair path for one that was missing
    /// that sync (see ADR-0017).
    func updateHomeGeofence(_ homeID: Int, forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws

    /// Removes a home area entirely.
    func deleteHomeGeofence(_ homeID: Int) async throws

    /// Excursions, trips away from home and back, within a time range,
    /// most recent first. Requires at least one home geofence to already be
    /// set; returns an empty array otherwise. With multiple homes, an
    /// excursion's start and end can be different homes (see ADR-0016).
    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion]

    /// Total distance and time away across every excursion the pet has ever
    /// taken. Implementations are expected to cache completed excursions'
    /// contributions so this doesn't re-walk the pet's whole history on
    /// every call, only an ongoing excursion (if any) is recomputed fresh.
    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats

    /// What the signed-in Traccar account can actually do, read straight off
    /// Traccar's own permission flags, not an app-level restriction (see
    /// ADR-0023).
    func currentUserPermissions() async throws -> AccountPermissions

    /// Shares a pet with another Traccar user, found by email, admin-only
    /// server-side, same as the rest of ADR-0018. Throws if no user with
    /// that email exists on this server.
    func sharePet(forPetID petID: Int, withEmail email: String) async throws
}
