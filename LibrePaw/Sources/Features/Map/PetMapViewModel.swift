import Foundation
import LibrePawKit

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
    /// ``stopLiveUpdates()`` is called, retrying on its own after a failure
    /// (see ``LivePetFeed``), the error capsule clears with the next update.
    func startLiveUpdates() {
        guard liveUpdatesTask == nil else { return }
        let petRepository = petRepository
        liveUpdatesTask = Task { [weak self] in
            await LivePetFeed.run(petRepository) { updatedPets in
                guard let self else { return false }
                self.pets = updatedPets
                self.errorMessage = nil
                return true
            } onError: { error in
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func stopLiveUpdates() {
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
    }
}
