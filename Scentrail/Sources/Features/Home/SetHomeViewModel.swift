import Foundation
import ScentrailKit

@Observable
@MainActor
final class SetHomeViewModel {
    let pet: Pet
    let locationService: LocationService

    /// The pin's current position — editable by dragging the map underneath
    /// it. Starts at the existing home if one is set, otherwise at the
    /// owner's current location once that becomes available.
    var homeCoordinate: Coordinate?
    var radiusMeters: Double = 50
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
        guard let home = try? await petRepository.homeGeofence(forPetID: pet.id) else {
            useCurrentLocationIfUnset()
            return
        }
        existingHome = home
        homeCoordinate = home.center
        radiusMeters = home.radiusMeters
    }

    /// Defaults the pin to the owner's current location, but only before
    /// there's anything else to show it at — never overrides an existing
    /// home or a position the owner already dragged the pin to.
    func useCurrentLocationIfUnset() {
        guard homeCoordinate == nil, let coordinate = locationService.coordinate else { return }
        homeCoordinate = coordinate
    }

    func saveHome() async {
        guard let coordinate = homeCoordinate else {
            errorMessage = "Drag the map to choose a location for home first."
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
