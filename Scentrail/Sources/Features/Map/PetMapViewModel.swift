import Foundation
import ScentrailKit

@Observable
@MainActor
final class PetMapViewModel {
    private(set) var pets: [Pet] = []
    private(set) var errorMessage: String?
    private let petRepository: PetRepository
    private var liveUpdatesTask: Task<Void, Never>?

    init(petRepository: PetRepository) {
        self.petRepository = petRepository
    }

    var petsWithPosition: [Pet] {
        pets.filter { $0.lastPosition != nil }
    }

    /// Subscribes to Traccar's live feed (see ADR-0013) until
    /// ``stopLiveUpdates()`` is called. The stream itself handles
    /// reconnection on transient drops.
    func startLiveUpdates() {
        guard liveUpdatesTask == nil else { return }
        liveUpdatesTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await updatedPets in self.petRepository.livePetUpdates() {
                    self.pets = updatedPets
                    self.errorMessage = nil
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func stopLiveUpdates() {
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
    }
}
