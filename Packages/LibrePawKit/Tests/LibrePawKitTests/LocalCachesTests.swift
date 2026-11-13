import Foundation
import Testing
@testable import LibrePawKit

// Serialized because all tests share one UserDefaults suite name.
@Suite("LocalCaches", .serialized)
struct LocalCachesTests {
    private let host = "traccar.example.com"

    private func makeDefaults() -> UserDefaults {
        let suiteName = "org.librepaw.app.localCaches.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func populate(_ defaults: UserDefaults) {
        UserDefaultsExcursionCacheStore(defaults: defaults).save(
            CachedExcursions(excursions: [], coveredFrom: .now, cachedThroughEndTime: .now),
            forPetID: 1,
            serverHost: host
        )
        UserDefaultsLifetimeStatsStore(defaults: defaults).save(
            CachedLifetimeStats(totalDistanceMeters: 1, totalDurationSeconds: 1, cachedThroughEndTime: .now),
            forPetID: 1,
            serverHost: host
        )
        defaults.set(Data(), forKey: "org.librepaw.excursionsCache.\(host).1") // a pre-v2 key
        defaults.set("dark", forKey: "org.librepaw.appearance") // an unrelated preference
    }

    @Test("clearAll removes both caches, legacy keys included, and nothing else")
    func clearAllRemovesOnlyCaches() {
        let defaults = makeDefaults()
        populate(defaults)

        LocalCaches.clearAll(in: defaults)

        #expect(UserDefaultsExcursionCacheStore(defaults: defaults).load(forPetID: 1, serverHost: host) == nil)
        #expect(UserDefaultsLifetimeStatsStore(defaults: defaults).load(forPetID: 1, serverHost: host) == nil)
        #expect(defaults.data(forKey: "org.librepaw.excursionsCache.\(host).1") == nil)
        #expect(defaults.string(forKey: "org.librepaw.appearance") == "dark")
    }

    @Test("Logging out clears the previous account's caches")
    func logOutClearsCaches() throws {
        let defaults = makeDefaults()
        populate(defaults)
        let service = LiveAuthenticationService(credentialStore: InMemoryCredentialStore(), cacheDefaults: defaults)

        try service.logOut()

        #expect(UserDefaultsExcursionCacheStore(defaults: defaults).load(forPetID: 1, serverHost: host) == nil)
        #expect(UserDefaultsLifetimeStatsStore(defaults: defaults).load(forPetID: 1, serverHost: host) == nil)
    }

    @Test("Caches are cleared even when the Keychain delete itself fails")
    func logOutClearsCachesEvenIfKeychainFails() {
        let defaults = makeDefaults()
        populate(defaults)
        let service = LiveAuthenticationService(credentialStore: FailingCredentialStore(), cacheDefaults: defaults)

        #expect(throws: KeychainError.self) { try service.logOut() }
        #expect(UserDefaultsExcursionCacheStore(defaults: defaults).load(forPetID: 1, serverHost: host) == nil)
    }
}

private final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var session: StoredSession?
    func save(_ session: StoredSession) throws { self.session = session }
    func loadSession() throws -> StoredSession? { session }
    func clear() throws { session = nil }
}

private struct FailingCredentialStore: CredentialStore {
    func save(_ session: StoredSession) throws { throw KeychainError.unhandled(status: -1) }
    func loadSession() throws -> StoredSession? { throw KeychainError.unhandled(status: -1) }
    func clear() throws { throw KeychainError.unhandled(status: -1) }
}
