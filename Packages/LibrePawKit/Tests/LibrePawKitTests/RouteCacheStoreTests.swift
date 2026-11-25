import Foundation
import Testing
@testable import LibrePawKit

@Suite("FileRouteCacheStore")
struct RouteCacheStoreTests {
    private func makeStore() -> FileRouteCacheStore {
        FileRouteCacheStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("routes-tests-\(UUID().uuidString)"))
    }

    private func position(_ id: Int) -> PetPosition {
        PetPosition(
            id: id,
            petID: 1,
            coordinate: Coordinate(latitude: 52.52, longitude: 13.405),
            recordedAt: Date(timeIntervalSince1970: 1_794_000_000 + Double(id)),
            speedKilometersPerHour: 3.5,
            address: nil,
            batteryLevelPercent: 80
        )
    }

    @Test("Round-trips a route keyed by pet, server and exact range")
    func roundTrips() {
        let store = makeStore()
        let from = Date(timeIntervalSince1970: 1_794_000_000.123)
        let to = Date(timeIntervalSince1970: 1_794_003_600.456)
        let route = [position(1), position(2)]

        store.save(route, forPetID: 1, serverHost: "traccar.example.com", from: from, to: to)

        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com", from: from, to: to) == route)
        #expect(store.load(forPetID: 2, serverHost: "traccar.example.com", from: from, to: to) == nil)
        #expect(store.load(forPetID: 1, serverHost: "other.example.com", from: from, to: to) == nil)
        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com", from: from, to: to.addingTimeInterval(1)) == nil)
    }

    @Test("Logging out removes cached routes along with the other caches")
    func clearedWithLocalCaches() {
        let store = makeStore()
        let from = Date(timeIntervalSince1970: 1_794_000_000)
        let to = from.addingTimeInterval(3_600)
        store.save([position(1)], forPetID: 1, serverHost: "traccar.example.com", from: from, to: to)
        let defaults = UserDefaults(suiteName: "org.librepaw.app.routes.tests")!

        LocalCaches.clearAll(in: defaults, routesDirectory: store.directory)

        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com", from: from, to: to) == nil)
    }
}
