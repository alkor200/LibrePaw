import Foundation
import TraccarKit

/// Default, server-backed implementation of ``AuthenticationService``.
public struct LiveAuthenticationService: AuthenticationService, @unchecked Sendable {
    private let credentialStore: CredentialStore
    /// Where `TraccarPetRepository`'s caches live, see ``LocalCaches``.
    private let cacheDefaults: UserDefaults

    public init(credentialStore: CredentialStore = KeychainCredentialStore()) {
        self.init(credentialStore: credentialStore, cacheDefaults: .standard)
    }

    init(credentialStore: CredentialStore, cacheDefaults: UserDefaults) {
        self.credentialStore = credentialStore
        self.cacheDefaults = cacheDefaults
    }

    public func restoreSession() throws -> StoredSession? {
        try credentialStore.loadSession()
    }

    @discardableResult
    public func logIn(serverURL: URL, email: String, password: String) async throws -> StoredSession {
        let credentials = TraccarCredentials(serverURL: serverURL, email: email, password: password)
        let client = TraccarClient(credentials: credentials)

        do {
            // Traccar's `GET /api/session` only checks for a cookie-based session
            // and ignores Basic Auth entirely (always 404 without a cookie), so it
            // cannot be used to validate credentials here. `/api/devices` is the
            // first endpoint we need anyway and correctly returns 401 for bad
            // credentials, so we use it to validate login (see ADR-0006).
            _ = try await client.fetchDevices()
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }

        // Starts every account from an empty cache, also covering caches
        // left behind by a build from before logOut cleared them.
        LocalCaches.clearAll(in: cacheDefaults)

        let session = StoredSession(serverURL: serverURL, email: email, password: password)
        try credentialStore.save(session)
        return session
    }

    public func logOut() throws {
        // First, and regardless of whether the Keychain delete below
        // succeeds: the cached data belongs to the account signing out.
        LocalCaches.clearAll(in: cacheDefaults)
        try credentialStore.clear()
    }

    public func makePetRepository(for session: StoredSession) -> PetRepository {
        let credentials = TraccarCredentials(serverURL: session.serverURL, email: session.email, password: session.password)
        return TraccarPetRepository(client: TraccarClient(credentials: credentials))
    }
}
