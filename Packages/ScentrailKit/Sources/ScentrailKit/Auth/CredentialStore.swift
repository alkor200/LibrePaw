import Foundation

/// Persists the active ``StoredSession``. See ADR-0007 for why this is a
/// Keychain-backed store rather than `UserDefaults`.
public protocol CredentialStore: Sendable {
    func save(_ session: StoredSession) throws
    func loadSession() throws -> StoredSession?
    func clear() throws
}
