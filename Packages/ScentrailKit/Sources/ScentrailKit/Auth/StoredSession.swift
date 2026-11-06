import Foundation

/// Everything needed to re-authenticate with a Traccar server, persisted in
/// the Keychain as a single item (see ADR-0007).
public struct StoredSession: Codable, Sendable, Equatable {
    public let serverURL: URL
    public let email: String
    public let password: String

    public init(serverURL: URL, email: String, password: String) {
        self.serverURL = serverURL
        self.email = email
        self.password = password
    }
}
