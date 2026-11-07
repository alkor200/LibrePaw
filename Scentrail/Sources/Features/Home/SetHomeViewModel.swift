import Foundation
import ScentrailKit

@Observable
@MainActor
final class SetHomeViewModel {
    let pet: Pet
    let locationService: LocationService

    var radiusMeters: Double = 100
    private(set) var existingHome: HomeGeofence?
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false

    private let petRepository: PetRepository

    init(pet: Pet, petRepository: PetRepository, locationService: LocationService) {
        self.pet = pet
        self.petRepository = petRepository
        self.locationService = locationService
    }

    func loadExistingHome() async {
        guard let home = try? await petRepository.homeGeofence(forPetID: pet.id) else { return }
        existingHome = home
        radiusMeters = home.radiusMeters
    }

    func saveHome() async {
        guard let coordinate = locationService.coordinate else {
            errorMessage = "Still finding your location — try again in a moment."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await petRepository.setHomeGeofence(forPetID: pet.id, center: coordinate, radiusMeters: radiusMeters)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
