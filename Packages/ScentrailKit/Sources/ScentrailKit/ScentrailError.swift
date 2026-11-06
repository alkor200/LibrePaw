import Foundation
import TraccarKit

/// Errors surfaced by `ScentrailKit`'s services and repositories.
///
/// `TraccarKit`'s own ``TraccarError`` never crosses this boundary (see
/// ADR-0005) — it is always mapped to one of these cases instead.
public enum ScentrailError: Error, Sendable, Equatable {
    case invalidCredentials
    case network(String)
    case unexpected(String)
}

extension ScentrailError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The email or password is incorrect."
        case .network(let message):
            message
        case .unexpected(let message):
            message
        }
    }
}

extension TraccarError {
    var asScentrailError: ScentrailError {
        switch self {
        case .invalidCredentials:
            .invalidCredentials
        case .transport(let message):
            .network(message)
        case .server, .decoding, .invalidServerURL:
            .unexpected(localizedDescription)
        }
    }
}
