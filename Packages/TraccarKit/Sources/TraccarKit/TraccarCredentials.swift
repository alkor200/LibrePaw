import Foundation

/// Credentials for a Traccar server, sent as HTTP Basic Authentication on every request.
///
/// See ADR-0006 for why the client is stateless (no cookie session) rather than
/// calling `POST /api/session` to establish one.
public struct TraccarCredentials: Sendable, Equatable {
    public let serverURL: URL
    public let email: String
    public let password: String

    public init(serverURL: URL, email: String, password: String) {
        self.serverURL = serverURL
        self.email = email
        self.password = password
    }

    /// The value of the `Authorization` header for HTTP Basic Auth.
    var basicAuthHeaderValue: String {
        let raw = "\(email):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}

extension TraccarCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    // Redacted so an accidental `print(credentials)` never leaks the password.
    public var description: String {
        "TraccarCredentials(serverURL: \(serverURL), email: \(email), password: <redacted>)"
    }

    public var debugDescription: String { description }
}
