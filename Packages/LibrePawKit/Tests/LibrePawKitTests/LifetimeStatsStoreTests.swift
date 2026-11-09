import Foundation
import Testing
@testable import LibrePawKit

// Serialized because all tests share one UserDefaults suite name.
@Suite("UserDefaultsLifetimeStatsStore", .serialized)
struct LifetimeStatsStoreTests {
    private func makeStore() -> UserDefaultsLifetimeStatsStore {
        let suiteName = "org.librepaw.app.lifetimeStats.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsLifetimeStatsStore(defaults: defaults)
    }

    @Test("load returns nil when nothing was saved for that pet")
    func loadReturnsNilWhenEmpty() {
        let store = makeStore()
        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com") == nil)
    }

    @Test("Round-trips cached stats through save and load")
    func savesAndLoadsStats() {
        let store = makeStore()
        let stats = CachedLifetimeStats(totalDistanceMeters: 1234, totalDurationSeconds: 5678, cachedThroughEndTime: .now)

        store.save(stats, forPetID: 1, serverHost: "traccar.example.com")
        let loaded = store.load(forPetID: 1, serverHost: "traccar.example.com")

        #expect(loaded?.totalDistanceMeters == stats.totalDistanceMeters)
        #expect(loaded?.totalDurationSeconds == stats.totalDurationSeconds)
        #expect(loaded?.cachedThroughEndTime == stats.cachedThroughEndTime)
    }

    @Test("Stats for different pets don't collide")
    func statsAreKeyedPerPet() {
        let store = makeStore()
        store.save(CachedLifetimeStats(totalDistanceMeters: 100, totalDurationSeconds: 60, cachedThroughEndTime: nil), forPetID: 1, serverHost: "traccar.example.com")
        store.save(CachedLifetimeStats(totalDistanceMeters: 200, totalDurationSeconds: 120, cachedThroughEndTime: nil), forPetID: 2, serverHost: "traccar.example.com")

        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com")?.totalDistanceMeters == 100)
        #expect(store.load(forPetID: 2, serverHost: "traccar.example.com")?.totalDistanceMeters == 200)
    }

    @Test("Stats for the same pet id on different servers don't collide")
    func statsAreKeyedPerServer() {
        let store = makeStore()
        store.save(CachedLifetimeStats(totalDistanceMeters: 100, totalDurationSeconds: 60, cachedThroughEndTime: nil), forPetID: 1, serverHost: "traccar.example.com")
        store.save(CachedLifetimeStats(totalDistanceMeters: 999, totalDurationSeconds: 999, cachedThroughEndTime: nil), forPetID: 1, serverHost: "other.example.com")

        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com")?.totalDistanceMeters == 100)
        #expect(store.load(forPetID: 1, serverHost: "other.example.com")?.totalDistanceMeters == 999)
    }

    @Test("clear discards a cached entry, load then returns nil again")
    func clearDiscardsCachedStats() {
        let store = makeStore()
        store.save(CachedLifetimeStats(totalDistanceMeters: 100, totalDurationSeconds: 60, cachedThroughEndTime: .now), forPetID: 1, serverHost: "traccar.example.com")

        store.clear(forPetID: 1, serverHost: "traccar.example.com")

        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com") == nil)
    }

    @Test("clear only affects the given pet and server, not others")
    func clearIsScopedToPetAndServer() {
        let store = makeStore()
        store.save(CachedLifetimeStats(totalDistanceMeters: 100, totalDurationSeconds: 60, cachedThroughEndTime: nil), forPetID: 1, serverHost: "traccar.example.com")
        store.save(CachedLifetimeStats(totalDistanceMeters: 200, totalDurationSeconds: 120, cachedThroughEndTime: nil), forPetID: 2, serverHost: "traccar.example.com")
        store.save(CachedLifetimeStats(totalDistanceMeters: 999, totalDurationSeconds: 999, cachedThroughEndTime: nil), forPetID: 1, serverHost: "other.example.com")

        store.clear(forPetID: 1, serverHost: "traccar.example.com")

        #expect(store.load(forPetID: 1, serverHost: "traccar.example.com") == nil)
        #expect(store.load(forPetID: 2, serverHost: "traccar.example.com")?.totalDistanceMeters == 200)
        #expect(store.load(forPetID: 1, serverHost: "other.example.com")?.totalDistanceMeters == 999)
    }
}
