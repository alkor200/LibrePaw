import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("SetHomeViewModel")
@MainActor
struct SetHomeViewModelTests {
    private let pet = Pet(id: 1, name: "Buddy", species: nil, status: .online, lastSeenAt: nil, lastPosition: nil)

    private func makeViewModel(repository: FakePetRepository = FakePetRepository()) async -> SetHomeViewModel {
        let viewModel = SetHomeViewModel(pet: pet, existingHome: nil, petRepository: repository, locationService: LocationService())
        await viewModel.loadPermissionContext()
        return viewModel
    }

    @Test("Saving needs a location first")
    func saveRequiresLocation() async {
        let viewModel = await makeViewModel()

        await viewModel.save()

        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("Saving needs a non-blank name")
    func saveRequiresName() async {
        let viewModel = await makeViewModel()
        viewModel.homeCoordinate = Coordinate(latitude: 51.31, longitude: 12.42)
        viewModel.name = "   "

        await viewModel.save()

        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("A read-only account can't save, even if the view let it try")
    func readOnlyCannotSave() async {
        let viewModel = await makeViewModel(repository: FakePetRepository(isReadOnly: true))
        viewModel.homeCoordinate = Coordinate(latitude: 51.31, longitude: 12.42)

        await viewModel.save()

        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("A valid new home saves")
    func validHomeSaves() async {
        let viewModel = await makeViewModel()
        viewModel.homeCoordinate = Coordinate(latitude: 51.31, longitude: 12.42)

        await viewModel.save()

        #expect(viewModel.didSave == true)
        #expect(viewModel.errorMessage == nil)
    }
}

@Suite("SharePetViewModel")
@MainActor
struct SharePetViewModelTests {
    private let pet = Pet(id: 1, name: "Buddy", species: nil, status: .online, lastSeenAt: nil, lastPosition: nil)

    @Test("A blank email is rejected before calling the server")
    func blankEmailIsRejected() async {
        let viewModel = SharePetViewModel(pet: pet, petRepository: FakePetRepository(sharePetError: LibrePawError.forbidden))
        viewModel.email = "  "

        await viewModel.share()

        #expect(viewModel.didShare == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("An unknown email surfaces the server's answer")
    func unknownEmailIsReported() async {
        let viewModel = SharePetViewModel(pet: pet, petRepository: FakePetRepository(sharePetError: LibrePawError.userNotFound))
        viewModel.email = "nobody@example.com"

        await viewModel.share()

        #expect(viewModel.didShare == false)
        #expect(viewModel.errorMessage == LibrePawError.userNotFound.userFacingMessage)
    }

    @Test("Sharing with a known email succeeds")
    func sharingSucceeds() async {
        let viewModel = SharePetViewModel(pet: pet, petRepository: FakePetRepository())
        viewModel.email = "friend@example.com"

        await viewModel.share()

        #expect(viewModel.didShare == true)
    }
}

@Suite("Excursion.routeText")
struct ExcursionRouteTextTests {
    private func excursion(from startHomeID: Int?, to endHomeID: Int?) -> Excursion {
        Excursion(
            id: 1,
            startTime: .now,
            endTime: .now,
            startCoordinate: nil,
            endCoordinate: nil,
            distanceMeters: nil,
            startHomeID: startHomeID,
            endHomeID: endHomeID
        )
    }

    @Test("A round trip to the same home has no route text")
    func roundTripHasNoRoute() {
        #expect(excursion(from: 1, to: 1).routeText { _ in "Home" } == nil)
    }

    @Test("Two different homes sharing a name are still a route")
    func sameNamedHomesAreARoute() {
        #expect(excursion(from: 1, to: 2).routeText { _ in "Home" } == "Home → Home")
    }

    @Test("An unknown home means no route text")
    func unknownHomeHasNoRoute() {
        #expect(excursion(from: 1, to: 2).routeText { $0 == 1 ? "Home" : nil } == nil)
    }
}
