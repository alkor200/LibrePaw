import Foundation
import TraccarKit

/// Errors surfaced by `LibrePawKit`'s services and repositories.
///
/// `TraccarKit`'s own ``TraccarError`` never crosses this boundary (see
/// ADR-0005), it is always mapped to one of these cases instead.
///
/// Each case is structured rather than carrying a ready-made sentence, so
/// the app can word it in the user's chosen language (see the app's
/// `Error.userFacingMessage`). `errorDescription` below is only an
/// English fallback, e.g. for logs and tests.
public enum LibrePawError: Error, Sendable, Equatable {
    case invalidCredentials
    /// Signed in fine, but not allowed to do this, see ``TraccarError/forbidden``.
    case forbidden
    /// The server couldn't be reached at all, with the system's own
    /// description of why (already in the device's language).
    case network(String)
    /// The server answered with an unexpected HTTP status.
    case server(statusCode: Int)
    /// The server answered, but not with anything LibrePaw understands.
    case unreadableResponse
    case invalidServerURL
    /// No Traccar user with the given email exists on this server.
    case userNotFound
}

extension LibrePawError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The email or password is incorrect."
        case .forbidden:
            "This account isn't allowed to do that on this server."
        case .network(let message):
            "Could not reach the server: \(message)"
        case .server(let statusCode):
            "The server responded with an unexpected status (\(statusCode))."
        case .unreadableResponse:
            "The server response could not be understood."
        case .invalidServerURL:
            "The server address is not a valid URL."
        case .userNotFound:
            "No Traccar user with that email was found on this server."
        }
    }
}

extension TraccarError {
    var asLibrePawError: LibrePawError {
        switch self {
        case .invalidCredentials:
            .invalidCredentials
        case .forbidden:
            .forbidden
        case .transport(let message):
            .network(message)
        case .server(let statusCode):
            .server(statusCode: statusCode)
        case .decoding:
            .unreadableResponse
        case .invalidServerURL:
            .invalidServerURL
        }
    }
}
