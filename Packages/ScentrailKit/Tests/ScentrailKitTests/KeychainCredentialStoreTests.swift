import Foundation
import Testing
@testable import ScentrailKit

// Serialized because all tests share one Keychain item (same service/account).
@Suite("KeychainCredentialStore", .serialized)
struct KeychainCredentialStoreTests {
    // A dedicated service name keeps these tests isolated from the app's real
    // stored session, which would use the default service name.
    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(service: "org.scentrail.app.session.tests")
    }

    @Test("Round-trips a session through save and loadSession")
    func savesAndLoadsSession() throws {
        let store = makeStore()
        try store.clear()
        defer { try? store.clear() }

        let session = StoredSession(
            serverURL: URL(string: "https://traccar.example.com")!,
            email: "owner@example.com",
            password: "super-secret"
        )

        try store.save(session)
        let loaded = try store.loadSession()

        #expect(loaded == session)
    }

    @Test("loadSession returns nil when nothing was saved")
    func loadSessionReturnsNilWhenEmpty() throws {
        let store = makeStore()
        try store.clear()

        #expect(try store.loadSession() == nil)
    }

    @Test("save overwrites a previously stored session")
    func saveOverwritesExistingSession() throws {
        let store = makeStore()
        try store.clear()
        defer { try? store.clear() }

        let first = StoredSession(serverURL: URL(string: "https://one.example.com")!, email: "a@example.com", password: "a")
        let second = StoredSession(serverURL: URL(string: "https://two.example.com")!, email: "b@example.com", password: "b")

        try store.save(first)
        try store.save(second)

        #expect(try store.loadSession() == second)
    }

    @Test("clear removes the stored session")
    func clearRemovesSession() throws {
        let store = makeStore()
        try store.save(StoredSession(serverURL: URL(string: "https://example.com")!, email: "a@example.com", password: "a"))

        try store.clear()

        #expect(try store.loadSession() == nil)
    }
}
