import Foundation
import Testing
@testable import LibrePawKit

// Serialized because all tests share one UserDefaults suite name.
@Suite("LiveAuthenticationService pending logout", .serialized)
struct PendingLogoutTests {
    private let session = StoredSession(serverURL: URL(string: "https://traccar.example.com")!, email: "owner@example.com", password: "secret")

    private func makeDefaults() -> UserDefaults {
        let suiteName = "org.librepaw.app.pendingLogout.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("A logout whose Keychain delete failed doesn't silently log back in on the next launch")
    func failedLogoutIsFinishedOnRestore() throws {
        let defaults = makeDefaults()
        let store = FlakyCredentialStore(session: session)
        let service = LiveAuthenticationService(credentialStore: store, defaults: defaults)

        store.failsToClear = true
        #expect(throws: KeychainError.self) { try service.logOut() }

        // Next launch, the Keychain cooperates again.
        store.failsToClear = false
        #expect(try service.restoreSession() == nil)
        #expect(store.storedSession == nil)
        #expect(defaults.bool(forKey: LiveAuthenticationService.pendingLogoutKey) == false)
    }

    @Test("While the delete keeps failing, nothing is restored and the marker stays")
    func persistentFailureStillRestoresNothing() throws {
        let defaults = makeDefaults()
        let store = FlakyCredentialStore(session: session)
        store.failsToClear = true
        let service = LiveAuthenticationService(credentialStore: store, defaults: defaults)

        #expect(throws: KeychainError.self) { try service.logOut() }
        #expect(throws: KeychainError.self) { try service.restoreSession() }
        #expect(defaults.bool(forKey: LiveAuthenticationService.pendingLogoutKey) == true)
    }

    @Test("A normal restore still returns the stored session")
    func normalRestore() throws {
        let service = LiveAuthenticationService(credentialStore: FlakyCredentialStore(session: session), defaults: makeDefaults())
        #expect(try service.restoreSession() == session)
    }
}

private final class FlakyCredentialStore: CredentialStore, @unchecked Sendable {
    var storedSession: StoredSession?
    var failsToClear = false

    init(session: StoredSession?) {
        storedSession = session
    }

    func save(_ session: StoredSession) throws { storedSession = session }
    func loadSession() throws -> StoredSession? { storedSession }
    func clear() throws {
        if failsToClear { throw KeychainError.unhandled(status: errSecInteractionNotAllowed) }
        storedSession = nil
    }
}
