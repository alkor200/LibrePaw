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
    /// Gates the "Share `<Pet>`" action, the "Edit `<Pet>`" row (name and
    /// photo), and the Trail/Excursions rows, each straight off what
    /// Traccar's own permission flags allow the signed-in account to do (see
    /// ADR-0018, ADR-0023). `nil` until ``loadPermissions()`` resolves. Edit
    /// and Share stay hidden until then, Trail and Excursions are shown
    /// right away and only removed if this turns out to deny them, so
    /// nothing shifts under the user's finger once it arrives (see
    /// `PetDetailView.actionsCard`).
    private(set) var permissions: AccountPermissions?
    /// This pet's tracker's own voltage-to-charge curve, for a tracker that
    /// reports only its battery voltage (see `PetRepository.batteryCurve`).
    private(set) var batteryCurve: BatteryCurve = .generic
    /// The tracker's voltage reports over the last
    /// `BatteryCalibration.smoothingWindow`, so ``battery`` can read the
    /// level from their median rather than from the latest report alone,
    /// which sags whenever the tracker is busy.
    private var recentVoltages: [BatteryCalibration.Sample] = []

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

    /// What this screen loads besides the live pet itself (permissions
    /// and the battery curve, the statistics moved to `StatsView`), but
    /// only when the last load is older than `maxAge`.
    ///
    /// The view calls this from `.task`, which runs again every time a
    /// pushed screen (Trail, Excursions, Homes, ...) pops back here.
    /// Permissions don't change while signed in, so they're only ever
    /// loaded until they succeed.
    func loadIfStale(maxAge: TimeInterval = 60) async {
        if let lastLoadedAt, Date.now.timeIntervalSince(lastLoadedAt) < maxAge { return }
        async let permissions: Void = permissions == nil ? loadPermissions() : ()
        async let battery: Void = loadBatteryCurve()
        _ = await (permissions, battery)
        // A load cut short (e.g. tapping into a sub-screen right away)
        // doesn't count, the next appearance should try again.
        if !Task.isCancelled {
            lastLoadedAt = .now
        }
    }

    func loadBatteryCurve() async {
        batteryCurve = await petRepository.batteryCurve(forPetID: pet.id)
        guard pet.lastPosition?.batteryLevelPercent == nil, pet.lastPosition?.batteryVoltage != nil else { return }
        let now = Date.now
        // Best-effort, without it the level is read from the latest report.
        guard let positions = try? await petRepository.fetchTrail(
            forPetID: pet.id,
            from: now.addingTimeInterval(-BatteryCalibration.smoothingWindow),
            to: now
        ) else { return }
        recentVoltages = positions.compactMap { position in
            position.batteryVoltage.map { BatteryCalibration.Sample(time: position.recordedAt, volts: $0) }
        }
    }

    /// The level to show: the tracker's own percentage when it reports
    /// one, otherwise estimated from its smoothed voltage, the recent
    /// reports plus whatever the live feed delivered since.
    var battery: BatteryReading? {
        guard let position = pet.lastPosition else { return nil }
        guard position.batteryLevelPercent == nil, let volts = position.batteryVoltage else {
            return position.battery(using: batteryCurve)
        }
        var samples = recentVoltages
        if samples.last.map({ $0.time < position.recordedAt }) ?? true {
            samples.append(BatteryCalibration.Sample(time: position.recordedAt, volts: volts))
        }
        let smoothed = BatteryCalibration.smoothed(samples).last?.volts ?? volts
        return BatteryReading(percent: batteryCurve.percent(forVoltage: smoothed), isEstimate: true)
    }

    /// Best-effort, this just gates UI affordances, not something worth
    /// surfacing an error for,
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
}
