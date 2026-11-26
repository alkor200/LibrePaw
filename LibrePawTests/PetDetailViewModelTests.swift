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

        #expect(repository.batteryCurveCalls.value == 1)
        #expect(viewModel.permissions != nil)
    }

    @Test("A load older than maxAge is repeated")
    func staleLoadIsRepeated() async {
        let repository = FakePetRepository()
        let viewModel = PetDetailViewModel(pet: pet, petRepository: repository)

        await viewModel.loadIfStale()
        await viewModel.loadIfStale(maxAge: 0)

        #expect(repository.batteryCurveCalls.value == 2)
    }

    @Test("The battery level is read from the recent reports' median, not a single sag")
    func batteryIgnoresSag() async throws {
        let now = Date.now
        func position(minutesAgo: Double, volts: Double) -> PetPosition {
            PetPosition(id: Int(minutesAgo), petID: 1, coordinate: Coordinate(latitude: 0, longitude: 0),
                        recordedAt: now.addingTimeInterval(-minutesAgo * 60), speedKilometersPerHour: 0,
                        address: nil, batteryLevelPercent: nil, batteryVoltage: volts)
        }
        var repository = FakePetRepository()
        repository.trail = [position(minutesAgo: 120, volts: 3.8), position(minutesAgo: 60, volts: 3.8)]
        // The latest report sagged while the tracker was sending.
        let sagging = Pet(id: 1, name: "Buddy", species: nil, status: .online, lastSeenAt: now,
                          lastPosition: position(minutesAgo: 0, volts: 3.4))
        let viewModel = PetDetailViewModel(pet: sagging, petRepository: repository)

        await viewModel.loadIfStale()

        let battery = try #require(viewModel.battery)
        #expect(battery.isEstimate)
        #expect(battery.percent == BatteryCurve.generic.percent(forVoltage: 3.8))
    }
}
