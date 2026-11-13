import Foundation
import LibrePawKit

@Observable
@MainActor
final class ExcursionsViewModel {
    let pet: Pet
    private(set) var excursions: [Excursion] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    /// Looked up alongside the excursions themselves so each row can show
    /// e.g. "Home → Cabin" when a trip started and ended at different homes
    /// (see ADR-0016) instead of just raw coordinates.
    private var homeNamesByID: [Int: String] = [:]

    private let petRepository: PetRepository
    private let lookbackDays: Int

    init(pet: Pet, petRepository: PetRepository, lookbackDays: Int = 7) {
        self.pet = pet
        self.petRepository = petRepository
        self.lookbackDays = lookbackDays
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await performLoad()
    }

    /// Reloads without touching `isLoading`, for `.refreshable`: toggling
    /// `isLoading` there would swap `ExcursionsView`'s `List` out for a
    /// full-screen `ProgressView` while the pull-to-refresh gesture is still
    /// in progress, tearing down the list (and the system refresh control's
    /// own task with it) and surfacing a spurious cancellation error on the
    /// very first pull (confirmed live; a subsequent "Try Again" tap always
    /// succeeded since it isn't tied to the list's lifecycle). Same fix as
    /// `PetListViewModel.refresh()`.
    func refresh() async {
        await performLoad()
    }

    private func performLoad() async {
        errorMessage = nil
        do {
            let from = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: .now) ?? .now
            async let fetchedExcursions = petRepository.fetchExcursions(forPetID: pet.id, from: from, to: .now)
            async let homes = petRepository.homeGeofences(forPetID: pet.id)
            excursions = try await fetchedExcursions
            homeNamesByID = Dictionary(uniqueKeysWithValues: try await homes.map { ($0.id, $0.name) })
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.userFacingMessage
        }
    }

    func homeName(forHomeID homeID: Int?) -> String? {
        guard let homeID else { return nil }
        return homeNamesByID[homeID]
    }
}
