import Foundation

/// A device as returned by Traccar's `/api/devices` endpoint.
///
/// In Traccar, a "device" is anything reporting GPS positions (a collar, an
/// OBD tracker, a phone running a tracking client). Scentrail maps this to
/// its own `Pet` domain model in `ScentrailKit`.
public struct TraccarDevice: Decodable, Sendable, Identifiable, Equatable {
    public enum Status: String, Decodable, Sendable {
        case online
        case offline
        case unknown
    }

    public let id: Int
    public let name: String
    public let uniqueId: String
    public let status: Status
    public let disabled: Bool
    public let lastUpdate: Date?
    public let positionId: Int?
    public let category: String?
    public let attributes: [String: JSONValue]

    public init(
        id: Int,
        name: String,
        uniqueId: String,
        status: Status,
        disabled: Bool,
        lastUpdate: Date?,
        positionId: Int?,
        category: String?,
        attributes: [String: JSONValue]
    ) {
        self.id = id
        self.name = name
        self.uniqueId = uniqueId
        self.status = status
        self.disabled = disabled
        self.lastUpdate = lastUpdate
        self.positionId = positionId
        self.category = category
        self.attributes = attributes
    }
}
