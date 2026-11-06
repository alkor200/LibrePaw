import Foundation

/// The authenticated user, as returned by `GET /api/session`.
public struct TraccarUser: Decodable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let email: String

    public init(id: Int, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}
