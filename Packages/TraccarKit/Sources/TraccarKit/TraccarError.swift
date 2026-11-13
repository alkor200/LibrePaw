import Foundation

/// Errors surfaced by ``TraccarClient``.
public enum TraccarError: Error, Sendable, Equatable {
    /// The server rejected the supplied credentials (HTTP 401).
    case invalidCredentials
    /// The credentials are fine, but this account isn't allowed to do this
    /// particular thing (HTTP 403). Deliberately separate from
    /// ``invalidCredentials``: a permission problem must never read as
    /// "wrong password", let alone end the session.
    case forbidden
    /// The server returned a non-success status code other than 401/403.
    case server(statusCode: Int)
    /// The response body could not be decoded into the expected type.
    case decoding(String)
    /// The underlying `URLSession` transport failed (no connectivity, TLS error, etc).
    case transport(String)
    /// The supplied server URL could not be turned into a valid request URL.
    case invalidServerURL
}

extension TraccarError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The email or password is incorrect."
        case .forbidden:
            "This account isn't allowed to do that on this server."
        case .server(let statusCode):
            "The server responded with an unexpected status (\(statusCode))."
        case .decoding:
            "The server response could not be understood."
        case .transport(let message):
            "Could not reach the server: \(message)"
        case .invalidServerURL:
            "The server address is not a valid URL."
        }
    }
}
