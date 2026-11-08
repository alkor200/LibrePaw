import Foundation
import TraccarKit

/// Default, server-backed implementation of ``AuthenticationService``.
public struct LiveAuthenticationService: AuthenticationService {
    private let credentialStore: CredentialStore

    public init(credentialStore: CredentialStore = KeychainCredentialStore()) {
        self.credentialStore = credentialStore
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

        let session = StoredSession(serverURL: serverURL, email: email, password: password)
        try credentialStore.save(session)
        return session
    }

    public func logOut() throws {
        try credentialStore.clear()
    }

    public func makePetRepository(for session: StoredSession) -> PetRepository {
        let credentials = TraccarCredentials(serverURL: session.serverURL, email: session.email, password: session.password)
        return TraccarPetRepository(client: TraccarClient(credentials: credentials))
    }
}
