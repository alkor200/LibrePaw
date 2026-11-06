import Foundation
import ScentrailKit

@Observable
@MainActor
final class PetMapViewModel {
    private(set) var pets: [Pet] = []
    private(set) var errorMessage: String?
    private let petRepository: PetRepository
    private var pollingTask: Task<Void, Never>?

    init(petRepository: PetRepository) {
        self.petRepository = petRepository
    }

    var petsWithPosition: [Pet] {
        pets.filter { $0.lastPosition != nil }
    }

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
            pets = try await petRepository.fetchPets()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
