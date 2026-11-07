import Foundation
import ScentrailKit

@Observable
@MainActor
final class ExcursionDetailViewModel {
    let excursion: Excursion
    private let petID: Int
    private let petRepository: PetRepository

    private(set) var trail: [PetPosition] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    init(excursion: Excursion, petID: Int, petRepository: PetRepository) {
        self.excursion = excursion
        self.petID = petID
        self.petRepository = petRepository
    }

    func loadTrail() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            trail = try await petRepository.fetchTrail(forPetID: petID, from: excursion.startTime, to: excursion.endTime ?? .now)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
