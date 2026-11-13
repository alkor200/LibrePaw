import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("PetDetailViewModel")
@MainActor
struct PetDetailViewModelTests {
    private let pet = Pet(id: 1, name: "Buddy", species: nil, status: .online, lastSeenAt: nil, lastPosition: nil)

    @Test("Returning to the screen shortly after a full load doesn't reload everything")
    func recentLoadIsNotRepeated() async {
        let repository = FakePetRepository()
        let viewModel = PetDetailViewModel(pet: pet, petRepository: repository)

        await viewModel.loadIfStale()
        await viewModel.loadIfStale()

        #expect(repository.trailCalls.value == 1)
        #expect(viewModel.permissions != nil)
    }

    @Test("A load older than maxAge is repeated")
    func staleLoadIsRepeated() async {
        let repository = FakePetRepository()
        let viewModel = PetDetailViewModel(pet: pet, petRepository: repository)

        await viewModel.loadIfStale()
        await viewModel.loadIfStale(maxAge: 0)

        #expect(repository.trailCalls.value == 2)
    }

    @Test("A failed recalculation is reported instead of swallowed")
    func failedRecalculationIsReported() async {
        let viewModel = PetDetailViewModel(pet: pet, petRepository: FakePetRepository(lifetimeStatsError: LibrePawError.network("offline")))

        await viewModel.recalculate()

        #expect(viewModel.recalculateErrorMessage != nil)
    }
}
