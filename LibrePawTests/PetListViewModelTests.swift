import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("PetListViewModel")
@MainActor
struct PetListViewModelTests {
    @Test("A failed refresh before anything loaded shows the error screen")
    func failedFirstLoadShowsError() async {
        let viewModel = PetListViewModel(petRepository: FakePetRepository(error: LibrePawError.network("offline")))

        await viewModel.refresh()

        guard case .failed = viewModel.state else {
            Issue.record("Expected .failed, got \(viewModel.state)")
            return
        }
        #expect(viewModel.refreshErrorMessage == nil)
    }

    @Test("A failed refresh over a loaded list keeps the list and reports it separately")
    func failedRefreshKeepsList() async {
        let viewModel = PetListViewModel(petRepository: FakePetRepository(errorAfterFirstFetch: LibrePawError.network("offline")))
        await viewModel.refresh()
        await viewModel.refresh()

        guard case .loaded = viewModel.state else {
            Issue.record("Expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(viewModel.refreshErrorMessage != nil)
    }
}
