import Foundation
import ScentrailKit

@Observable
@MainActor
final class ExcursionsViewModel {
    let pet: Pet
    private(set) var excursions: [Excursion] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

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
            excursions = try await petRepository.fetchExcursions(forPetID: pet.id, from: from, to: .now)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
