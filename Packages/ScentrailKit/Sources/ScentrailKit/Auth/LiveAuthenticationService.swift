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
            _ = try await client.fetchCurrentUser()
        } catch let error as TraccarError {
            throw error.asScentrailError
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
