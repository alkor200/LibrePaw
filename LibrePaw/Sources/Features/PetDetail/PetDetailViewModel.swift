import Foundation
import LibrePawKit

@Observable
@MainActor
final class PetDetailViewModel {
    /// `private(set)`, not `let`: ``rename(to:)`` updates it in place after a
    /// successful save, so every reader (the header, `navigationTitle`, any
    /// pushed destination constructed from it) immediately reflects the new
    /// name without waiting for the next `fetchPets()`/`livePetUpdates()`
    /// refresh elsewhere in the app.
    private(set) var pet: Pet
    private(set) var trail: [PetPosition] = []
    private(set) var isLoadingTrail = false
    private(set) var trailErrorMessage: String?
    private(set) var lifetimeStats: LifetimeStats?
    private(set) var todaysExcursions: [Excursion] = []
    /// Gates the "Share `<Pet>`" action, the "Edit `<Pet>`" row (name and
    /// photo), and the Trail/Excursions rows, each straight off what
    /// Traccar's own permission flags allow the signed-in account to do (see
    /// ADR-0018, ADR-0023). `nil` until ``loadPermissions()`` resolves, every
    /// gated affordance stays hidden until then.
    private(set) var permissions: AccountPermissions?

    private let petRepository: PetRepository
    private var liveUpdatesTask: Task<Void, Never>?
    /// When ``loadIfStale(maxAge:)`` last finished a full load, `nil` before
    /// the first one (or while it's still running).
    private var lastLoadedAt: Date?

    init(pet: Pet, petRepository: PetRepository) {
        self.pet = pet
        self.petRepository = petRepository
    }

    /// Keeps `pet` (so `lastPosition`, `status`, `lastSeenAt`) current while
    /// this screen stays open, over Traccar's WebSocket feed (ADR-0013),
    /// same as `PetListViewModel.startLiveUpdates()`.
    ///
    /// Without this, `pet` was a one-time snapshot, exactly as it was when
    /// this screen was pushed, and the real tracker keeps reporting a new
    /// position every 30 seconds or so (see ADR-0025) the whole time this
    /// screen stays open. "View on Map" reads `pet.lastPosition` directly
    /// (see its header button below), so the longer this screen was open
    /// before tapping it, the further the pet had already moved on from
    /// wherever the map then centered on, confirmed live: this is exactly
    /// what read as "View on Map doesn't go to where the pet actually is".
    func startLiveUpdates() {
        guard liveUpdatesTask == nil else { return }
        let petID = pet.id
        let petRepository = petRepository
        // Best-effort: a failing feed just means the header/"View on Map"
        // go stale until it recovers on its own (see ``LivePetFeed``), not
        // worth surfacing as an error on top of this screen's other,
        // already-best-effort loads.
        liveUpdatesTask = Task { [weak self] in
            await LivePetFeed.run(petRepository) { pets in
                guard let self else { return false }
                if let updated = pets.first(where: { $0.id == petID }) {
                    self.pet = updated
                }
                return true
            }
        }
    }

    func stopLiveUpdates() {
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
    }

    /// Loads today's position history so the detail map can draw a trail.
    /// Everything this screen shows besides the live pet itself, loaded
    /// side by side, but only when the last full load is older than
    /// `maxAge`.
    ///
    /// The view calls this from `.task`, which runs again every time a
    /// pushed screen (Trail, Excursions, Homes, ...) pops back here.
    /// Reloading unconditionally meant re-fetching today's trail, the
    /// lifetime stats and today's excursion events on every single
    /// return, even seconds after the last load. Permissions don't change
    /// while signed in, so they're only ever loaded until they succeed.
    func loadIfStale(maxAge: TimeInterval = 60) async {
        if let lastLoadedAt, Date.now.timeIntervalSince(lastLoadedAt) < maxAge { return }
        async let trail: Void = loadTodaysTrail()
        async let stats: Void = loadLifetimeStats()
        async let excursions: Void = loadTodaysExcursions()
        async let permissions: Void = permissions == nil ? loadPermissions() : ()
        _ = await (trail, stats, excursions, permissions)
        // A load cut short (e.g. tapping into a sub-screen right away)
        // doesn't count, the next appearance should try again.
        if !Task.isCancelled {
            lastLoadedAt = .now
        }
    }

    func loadTodaysTrail() async {
        isLoadingTrail = true
        trailErrorMessage = nil
        defer { isLoadingTrail = false }

        do {
            let startOfDay = Calendar.current.startOfDay(for: .now)
            trail = try await petRepository.fetchTrail(forPetID: pet.id, from: startOfDay, to: .now)
        } catch {
            trailErrorMessage = error.userFacingMessage
        }
    }

    /// Lifetime distance/time-away totals. Best-effort: leaves the previous
    /// value (or `nil`) in place on failure rather than surfacing an error,
    /// since this is a secondary stat alongside today's trail.
    func loadLifetimeStats() async {
        lifetimeStats = try? await petRepository.lifetimeExcursionStats(forPetID: pet.id)
    }

    private(set) var isRecalculating = false

    /// Discards both the cached excursions and the cached lifetime totals
    /// built from them, then recomputes everything from the pet's entire
    /// excursion history (see
    /// `PetRepository.resetExcursionsCache(forPetID:)`/
    /// `resetLifetimeStats(forPetID:)`), for recovering from bad cached
    /// data, e.g. an excursion a since-fixed bug had closed wrong. Not
    /// something an ordinary user needs day to day, reached from a context
    /// menu on the lifetime stat tiles rather than a prominent button.
    ///
    /// Clears the excursions cache before the lifetime stats one: the
    /// latter is itself built from `fetchExcursions`, clearing it first
    /// would just re-read the still-bad cached excursions right back in.
    func recalculate() async {
        isRecalculating = true
        defer { isRecalculating = false }
        try? await petRepository.resetExcursionsCache(forPetID: pet.id)
        try? await petRepository.resetLifetimeStats(forPetID: pet.id)
        await loadLifetimeStats()
        await loadTodaysExcursions()
    }

    /// Today's excursions, for ``totalTimeAwayTodaySeconds``. Best-effort,
    /// same reasoning as ``loadLifetimeStats()``, and naturally empty (not
    /// an error) when the account has reports disabled, same as everything
    /// else built on ``PetRepository/fetchExcursions(forPetID:from:to:)``
    /// (see ADR-0023).
    func loadTodaysExcursions() async {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        todaysExcursions = (try? await petRepository.fetchExcursions(forPetID: pet.id, from: startOfDay, to: .now)) ?? []
    }

    /// Best-effort, same reasoning as ``loadLifetimeStats()``: this just
    /// gates UI affordances, not something worth surfacing an error for,
    /// but retried a few times (see `currentUserPermissionsRetrying`) so
    /// one dropped request doesn't hide them for good.
    func loadPermissions() async {
        permissions = await petRepository.currentUserPermissionsRetrying()
    }

    func setPhoto(jpegData: Data) async throws {
        try await petRepository.setPhoto(forPetID: pet.id, jpegData: jpegData)
    }

    func rename(to name: String) async throws {
        try await petRepository.renamePet(forPetID: pet.id, name: name)
        pet = Pet(
            id: pet.id,
            name: name,
            species: pet.species,
            status: pet.status,
            lastSeenAt: pet.lastSeenAt,
            lastPosition: pet.lastPosition,
            photoURL: pet.photoURL
        )
    }

    /// Total distance covered along today's trail, summing consecutive fixes
    /// with the same spherical-geometry math used by the Find Pet screen.
    /// `nil` until there are at least two points to measure between.
    var totalTrailDistanceMeters: Double? {
        guard trail.count > 1 else { return nil }
        return zip(trail, trail.dropFirst())
            .reduce(0) { $0 + $1.0.coordinate.distanceMeters(to: $1.1.coordinate) }
    }

    /// Total time spent away from home today, summing every excursion that
    /// started today (an ongoing one contributes its elapsed-so-far
    /// duration, same convention as `mergeLifetimeStats`). Likely-vehicle
    /// trips are excluded, same reasoning as the lifetime total: this is
    /// meant to read as time out and about, not time spent being driven
    /// somewhere. `nil` until there's at least one excursion to show.
    var totalTimeAwayTodaySeconds: TimeInterval? {
        let walked = todaysExcursions.filter { !$0.isLikelyVehicleTrip }
        guard !walked.isEmpty else { return nil }
        return walked.reduce(0) { total, excursion in
            total + (excursion.duration ?? Date.now.timeIntervalSince(excursion.startTime))
        }
    }
}
