import Foundation

/// A user as returned by `/api/users`, only the fields Scentrail needs to
/// identify "the currently authenticated user" and whether they're an
/// administrator (see ADR-0017, ADR-0018).
public struct TraccarUser: Decodable, Sendable, Equatable {
    public let id: Int
    public let email: String
    public let administrator: Bool

    public init(id: Int, email: String, administrator: Bool) {
        self.id = id
        self.email = email
        self.administrator = administrator
    }
}
