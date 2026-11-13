import Foundation
import LibrePawKit

extension Error {
    /// What to show the user for this error, in the app's own language
    /// (see ADR-0022). `localizedDescription` alone was English for every
    /// `LibrePawError` regardless of the selected language, and for a
    /// `KeychainError` just "The operation couldn't be completed."
    var userFacingMessage: String {
        if let error = self as? LibrePawError {
            return switch error {
            case .invalidCredentials:
                localized("The email or password is incorrect.")
            case .forbidden:
                localized("This account isn't allowed to do that on this server.")
            case .network(let message):
                localized("Could not reach the server: %@", message)
            case .server(let statusCode):
                localized("The server responded with an unexpected status (%lld).", statusCode)
            case .unreadableResponse:
                localized("The server response could not be understood.")
            case .invalidServerURL:
                localized("The server address is not a valid URL.")
            case .userNotFound:
                localized("No Traccar user with that email was found on this server.")
            }
        }
        if self is KeychainError {
            return localized("The login couldn't be saved on this device.")
        }
        return localizedDescription
    }
}
