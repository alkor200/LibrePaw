import Foundation
import ScentrailKit

@Observable
@MainActor
final class FindPetViewModel {
    private(set) var pet: Pet
    let locationService: LocationService

    private let petRepository: PetRepository
    private var liveUpdatesTask: Task<Void, Never>?

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
        startLiveUpdates()
    }

    func stop() {
        locationService.stopUpdating()
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
    }

    /// Subscribes to Traccar's live feed (see ADR-0013) so the pet's position
    /// — and therefore the arrow and distance — update in near real time.
    private func startLiveUpdates() {
        guard liveUpdatesTask == nil else { return }
        liveUpdatesTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await pets in self.petRepository.livePetUpdates() {
                    guard !Task.isCancelled else { break }
                    if let updated = pets.first(where: { $0.id == self.pet.id }) {
                        self.pet = updated
                    }
                }
            } catch {
                // Best-effort: keep showing the last known position rather
                // than surfacing a transient feed error on this screen.
            }
        }
    }
}

private extension Double {
    var normalizedDegrees: Double {
        let result = truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
