import Foundation
import Testing
@testable import ScentrailKit

// Serialized because all tests share one UserDefaults suite name.
@Suite("UserDefaultsLifetimeStatsStore", .serialized)
struct LifetimeStatsStoreTests {
    private func makeStore() -> UserDefaultsLifetimeStatsStore {
        let suiteName = "org.scentrail.app.lifetimeStats.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsLifetimeStatsStore(defaults: defaults)
    }

    @Test("load returns nil when nothing was saved for that pet")
    func loadReturnsNilWhenEmpty() {
        let store = makeStore()
        #expect(store.load(forPetID: 1) == nil)
    }

    @Test("Round-trips cached stats through save and load")
    func savesAndLoadsStats() {
        let store = makeStore()
        let stats = CachedLifetimeStats(totalDistanceMeters: 1234, totalDurationSeconds: 5678, cachedThroughEndTime: .now)

        store.save(stats, forPetID: 1)
        let loaded = store.load(forPetID: 1)

        #expect(loaded?.totalDistanceMeters == stats.totalDistanceMeters)
        #expect(loaded?.totalDurationSeconds == stats.totalDurationSeconds)
        #expect(loaded?.cachedThroughEndTime == stats.cachedThroughEndTime)
    }

    @Test("Stats for different pets don't collide")
    func statsAreKeyedPerPet() {
        let store = makeStore()
        store.save(CachedLifetimeStats(totalDistanceMeters: 100, totalDurationSeconds: 60, cachedThroughEndTime: nil), forPetID: 1)
        store.save(CachedLifetimeStats(totalDistanceMeters: 200, totalDurationSeconds: 120, cachedThroughEndTime: nil), forPetID: 2)

        #expect(store.load(forPetID: 1)?.totalDistanceMeters == 100)
        #expect(store.load(forPetID: 2)?.totalDistanceMeters == 200)
    }
}
