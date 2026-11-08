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
    /// ``stopLiveUpdates()`` is called. The stream itself handles
    /// reconnection on transient drops.
    func startLiveUpdates() {
        guard liveUpdatesTask == nil else { return }
        liveUpdatesTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await pets in self.petRepository.livePetUpdates() {
                    self.state = .loaded(self.sorted(pets))
                }
            } catch {
                if !Task.isCancelled {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
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
            state = .failed(error.localizedDescription)
        }
    }

    private func sorted(_ pets: [Pet]) -> [Pet] {
        pets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
