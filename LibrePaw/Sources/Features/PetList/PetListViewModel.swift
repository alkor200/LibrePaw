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
    /// A pull-to-refresh failed while a list was already showing. Shown as
    /// an alert over that list rather than replacing it with an error
    /// screen, the list itself (and the live feed behind it) is still fine.
    var refreshErrorMessage: String?
    /// Bumped by every live update, so ``refresh()`` can tell whether one
    /// arrived while its REST request was in flight.
    private var liveUpdateCount = 0
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
                self.liveUpdateCount += 1
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

    /// A manual pull-to-refresh (or Try Again): fetches once over REST,
    /// independent of the live stream (which keeps running in the
    /// background regardless).
    func refresh() async {
        let liveUpdateCountBefore = liveUpdateCount
        do {
            let pets = try await petRepository.fetchPets()
            // A live update that arrived meanwhile is at least as fresh as
            // this snapshot, don't roll it back.
            guard liveUpdateCount == liveUpdateCountBefore else { return }
            state = .loaded(sorted(pets))
        } catch {
            if hasLoadedPets {
                refreshErrorMessage = error.userFacingMessage
            } else {
                state = .failed(error.userFacingMessage)
            }
        }
    }

    private func sorted(_ pets: [Pet]) -> [Pet] {
        pets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
