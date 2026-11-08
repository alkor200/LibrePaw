import Foundation
import ScentrailKit

/// Lists a pet's home geofences and lets the owner delete one (adding and
/// editing happen in ``SetHomeView``, pushed from here — see ADR-0016).
///
/// Only reachable from an admin account at all — `PetDetailView` hides the
/// entry point to this screen entirely for a non-admin (see ADR-0018), so
/// nothing here needs its own admin check.
@Observable
@MainActor
final class HomesViewModel {
    let pet: Pet
    private(set) var homes: [HomeGeofence] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    private let petRepository: PetRepository
    /// The most recently started load, so a newer one can cancel a stale one
    /// still in flight instead of letting both race to set `homes`.
    private var loadTask: Task<Void, Never>?

    init(pet: Pet, petRepository: PetRepository) {
        self.pet = pet
        self.petRepository = petRepository
    }

    /// `HomesView` calls this from `.onAppear` (fires every time the view is
    /// revisited — e.g. after editing a home — see its doc comment) as well
    /// as `.refreshable`, so two loads can legitimately overlap: editing a
    /// home and popping back can retrigger a load while a slightly earlier
    /// one is still in flight. Cancelling the previous one here, rather than
    /// letting both run, avoids a race where the loser finishes later and
    /// clobbers the winner's result — and `performLoad` below treats
    /// cancellation as "superseded," not a failure, so the loser never
    /// flashes a spurious "cancelled" error over a load that actually
    /// succeeded.
    func load() async {
        loadTask?.cancel()
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            homes = try await petRepository.homeGeofences(forPetID: pet.id)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ home: HomeGeofence) async {
        do {
            try await petRepository.deleteHomeGeofence(home.id)
            homes.removeAll { $0.id == home.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
