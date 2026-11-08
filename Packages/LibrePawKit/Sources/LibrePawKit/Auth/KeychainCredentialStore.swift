import Foundation
import Security

/// A `CredentialStore` backed by the iOS Keychain. Stores the whole
/// ``StoredSession`` as a single JSON-encoded generic password item so that
/// saving/clearing a session is one atomic operation (see ADR-0007).
public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account = "current-session"

    /// - Parameter service: the Keychain item's `kSecAttrService`. Tests pass
    ///   a dedicated value so they never touch the app's real stored session.
    public init(service: String = "org.librepaw.app.session") {
        self.service = service
    }

    public func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)

        // Remove any existing item first so `save` behaves as an upsert.
        SecItemDelete(query() as CFDictionary)

        var attributes = query()
        attributes[kSecValueData as String] = data
        // ThisDeviceOnly keeps the stored password out of encrypted backups -
        // it should never be restorable onto a different device.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    public func loadSession() throws -> StoredSession? {
        var matchQuery = query()
        matchQuery[kSecReturnData as String] = true
        matchQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(matchQuery as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try JSONDecoder().decode(StoredSession.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status: status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public enum KeychainError: Error, Sendable, Equatable {
    case unhandled(status: OSStatus)
}
