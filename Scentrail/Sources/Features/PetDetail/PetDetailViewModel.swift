import Foundation
import ScentrailKit

@Observable
@MainActor
final class PetDetailViewModel {
    let pet: Pet
    private(set) var trail: [PetPosition] = []
    private(set) var isLoadingTrail = false
    private(set) var trailErrorMessage: String?

    private let petRepository: PetRepository

    init(pet: Pet, petRepository: PetRepository) {
        self.pet = pet
        self.petRepository = petRepository
    }

    /// Loads today's position history so the detail map can draw a trail.
    func loadTodaysTrail() async {
        isLoadingTrail = true
        trailErrorMessage = nil
        defer { isLoadingTrail = false }

        do {
            let startOfDay = Calendar.current.startOfDay(for: .now)
            trail = try await petRepository.fetchTrail(forPetID: pet.id, from: startOfDay, to: .now)
        } catch {
            trailErrorMessage = error.localizedDescription
        }
    }
}
