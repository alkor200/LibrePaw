import Foundation
import ScentrailKit

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
    private var pollingTask: Task<Void, Never>?

    init(petRepository: PetRepository) {
        self.petRepository = petRepository
    }

    /// Refreshes immediately, then keeps refreshing on `interval` until
    /// ``stopPolling()`` is called (see ADR-0006 for why we poll rather than
    /// use a WebSocket feed).
    func startPolling(interval: Duration = .seconds(20)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        do {
            let pets = try await petRepository.fetchPets()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            state = .loaded(pets)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
