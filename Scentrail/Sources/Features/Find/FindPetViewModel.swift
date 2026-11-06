import Foundation
import ScentrailKit

@Observable
@MainActor
final class FindPetViewModel {
    private(set) var pet: Pet
    let locationService: LocationService

    private let petRepository: PetRepository
    private var pollingTask: Task<Void, Never>?

    init(pet: Pet, petRepository: PetRepository, locationService: LocationService) {
        self.pet = pet
        self.petRepository = petRepository
        self.locationService = locationService
    }

    var distanceMeters: Double? {
        guard let userCoordinate = locationService.coordinate, let petCoordinate = pet.lastPosition?.coordinate else {
            return nil
        }
        return userCoordinate.distanceMeters(to: petCoordinate)
    }

    /// Degrees to rotate the on-screen arrow so it points toward the pet,
    /// relative to the top of the screen — i.e. already corrected for the
    /// device's own compass heading when one is available.
    var arrowRotationDegrees: Double? {
        guard let userCoordinate = locationService.coordinate, let petCoordinate = pet.lastPosition?.coordinate else {
            return nil
        }
        let bearing = userCoordinate.initialBearingDegrees(to: petCoordinate)
        let heading = locationService.isHeadingAvailable ? (locationService.headingDegrees ?? bearing) : 0
        return (bearing - heading).normalizedDegrees
    }

    func start() {
        locationService.requestAuthorizationIfNeeded()
        locationService.startUpdating()
        startPolling()
    }

    func stop() {
        locationService.stopUpdating()
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPolling(interval: Duration = .seconds(10)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshPet()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func refreshPet() async {
        guard let pets = try? await petRepository.fetchPets(),
              let updated = pets.first(where: { $0.id == pet.id }) else { return }
        pet = updated
    }
}

private extension Double {
    var normalizedDegrees: Double {
        let result = truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
