import Foundation

/// Authenticates against a Traccar server and vends a ``PetRepository`` for
/// the active session.
///
/// This is the only `ScentrailKit` type that knows how to construct a
/// `TraccarKit` client — see ADR-0005. Nothing in the `Scentrail` app target
/// needs to `import TraccarKit`.
public protocol AuthenticationService: Sendable {
    /// The session persisted from a previous launch, if any. Does not
    /// validate it against the server — that happens lazily on first use.
    func restoreSession() throws -> StoredSession?

    /// Validates the given credentials against the server and, on success,
    /// persists them for future launches.
    @discardableResult
    func logIn(serverURL: URL, email: String, password: String) async throws -> StoredSession

    /// Clears the persisted session. Does not call the server (Traccar has
    /// no server-side session to invalidate when using Basic Auth; see
    /// ADR-0006).
    func logOut() throws

    /// Builds a `PetRepository` that authenticates as the given session.
    func makePetRepository(for session: StoredSession) -> PetRepository
}
