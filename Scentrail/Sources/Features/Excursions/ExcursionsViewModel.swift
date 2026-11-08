import Foundation
import ScentrailKit

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
        errorMessage = nil
        defer { isLoading = false }

        do {
            let from = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: .now) ?? .now
            async let fetchedExcursions = petRepository.fetchExcursions(forPetID: pet.id, from: from, to: .now)
            async let homes = petRepository.homeGeofences(forPetID: pet.id)
            excursions = try await fetchedExcursions
            homeNamesByID = Dictionary(uniqueKeysWithValues: try await homes.map { ($0.id, $0.name) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func homeName(forHomeID homeID: Int?) -> String? {
        guard let homeID else { return nil }
        return homeNamesByID[homeID]
    }
}
