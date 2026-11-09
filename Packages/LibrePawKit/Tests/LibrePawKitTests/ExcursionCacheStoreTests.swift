import Foundation
import Testing
@testable import LibrePawKit

// Serialized because all tests share one UserDefaults suite name.
@Suite("UserDefaultsExcursionCacheStore", .serialized)
struct ExcursionCacheStoreTests {
    private func makeStore() -> UserDefaultsExcursionCacheStore {
        let suiteName = "org.librepaw.app.excursionsCache.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsExcursionCacheStore(defaults: defaults)
    }

    private func excursion(id: Int) -> Excursion {
        Excursion(id: id, startTime: .now, endTime: .now, startCoordinate: nil, endCoordinate: nil, distanceMeters: nil)
    }

    @Test("load returns nil when nothing was saved for that pet")
    func loadReturnsNilWhenEmpty() {
        let store = makeStore()
        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com") == nil)
    }

    @Test("Round-trips cached excursions through save and load")
    func savesAndLoadsExcursions() {
        let store = makeStore()
        let cached = CachedExcursions(excursions: [excursion(id: 1), excursion(id: 2)], cachedThroughEndTime: .now)

        store.save(cached, forPetID: 1, serverHost: "traccar.example.com")
        let loaded = store.load(forPetID: 1, serverHost: "traccar.example.com")

        #expect(loaded?.excursions.map(\.id) == cached.excursions.map(\.id))
        #expect(loaded?.cachedThroughEndTime == cached.cachedThroughEndTime)
    }

    @Test("Cached excursions for different pets don't collide")
    func excursionsAreKeyedPerPet() {
        let store = makeStore()
        store.save(CachedExcursions(excursions: [excursion(id: 1)], cachedThroughEndTime: nil), forPetID: 1, serverHost: "traccar.example.com")
        store.save(CachedExcursions(excursions: [excursion(id: 2)], cachedThroughEndTime: nil), forPetID: 2, serverHost: "traccar.example.com")

        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com")?.excursions.map(\.id) == [1])
        #expect(store.load(forPetID: 2, serverHost: "traccar.example.com")?.excursions.map(\.id) == [2])
    }

    @Test("clear discards a cached entry, load then returns nil again")
    func clearDiscardsCachedExcursions() {
        let store = makeStore()
        store.save(CachedExcursions(excursions: [excursion(id: 1)], cachedThroughEndTime: .now), forPetID: 1, serverHost: "traccar.example.com")

        store.clear(forPetID: 1, serverHost: "traccar.example.com")

        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com") == nil)
    }
}
