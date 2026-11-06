import Foundation

/// A single GPS fix as returned by Traccar's `/api/positions` endpoint.
public struct TraccarPosition: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let deviceId: Int
    public let fixTime: Date
    public let latitude: Double
    public let longitude: Double
    /// Speed over ground, in knots (Traccar's native unit).
    public let speed: Double
    /// Course over ground, in degrees.
    public let course: Double
    public let address: String?
    public let attributes: [String: JSONValue]

    public init(
        id: Int,
        deviceId: Int,
        fixTime: Date,
        latitude: Double,
        longitude: Double,
        speed: Double,
        course: Double,
        address: String?,
        attributes: [String: JSONValue]
    ) {
        self.id = id
        self.deviceId = deviceId
        self.fixTime = fixTime
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.course = course
        self.address = address
        self.attributes = attributes
    }

    /// Battery level percentage (0-100), when reported by the tracker hardware.
    /// Traccar conventionally reports this under the `batteryLevel` attribute.
    public var batteryLevel: Double? {
        attributes["batteryLevel"]?.doubleValue
    }
}
