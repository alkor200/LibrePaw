import Foundation
import LibrePawKit

@Observable
@MainActor
final class ExcursionDetailViewModel {
    let excursion: Excursion
    private let petID: Int
    private let petRepository: PetRepository

    private(set) var trail: [PetPosition] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private var homeNamesByID: [Int: String] = [:]

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
            async let fetchedTrail = petRepository.fetchTrail(forPetID: petID, from: excursion.startTime, to: excursion.endTime ?? .now)
            async let homes = petRepository.homeGeofences(forPetID: petID)
            trail = try await fetchedTrail
            homeNamesByID = Dictionary(uniqueKeysWithValues: try await homes.map { ($0.id, $0.name) })
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    /// See ``LibrePawKit/Excursion/routeText(homeName:)``.
    var routeText: String? {
        excursion.routeText { homeNamesByID[$0] }
    }
}
