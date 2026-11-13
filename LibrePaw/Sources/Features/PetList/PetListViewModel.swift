import Foundation
import LibrePawKit

@Observable
@MainActor
final class PetListViewModel {
    enum LoadState {
        case loading
        case loaded([Pet])
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private let petRepository: PetRepository
    private var liveUpdatesTask: Task<Void, Never>?

    init(petRepository: PetRepository) {
        self.petRepository = petRepository
    }

    /// Subscribes to Traccar's live feed (see ADR-0013) until
    /// ``stopLiveUpdates()`` is called, retrying on its own after a failure
    /// (see ``LivePetFeed``). A failure only replaces the screen with an
    /// error while there's nothing loaded yet, an already-loaded list stays
    /// up (if briefly stale) while the feed retries.
    func startLiveUpdates() {
        guard liveUpdatesTask == nil else { return }
        let petRepository = petRepository
        liveUpdatesTask = Task { [weak self] in
            await LivePetFeed.run(petRepository) { pets in
                guard let self else { return false }
                self.state = .loaded(self.sorted(pets))
                return true
            } onError: { error in
                guard let self, !self.hasLoadedPets else { return }
                self.state = .failed(error.userFacingMessage)
            }
        }
    }

    private var hasLoadedPets: Bool {
        if case .loaded = state { return true }
        return false
    }

    func stopLiveUpdates() {
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
    }

    /// A manual pull-to-refresh: fetches once over REST, independent of the
    /// live stream (which keeps running in the background regardless).
    func refresh() async {
        do {
            state = .loaded(sorted(try await petRepository.fetchPets()))
        } catch {
            state = .failed(error.userFacingMessage)
        }
    }

    private func sorted(_ pets: [Pet]) -> [Pet] {
        pets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
