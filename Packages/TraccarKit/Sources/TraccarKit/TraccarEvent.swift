import Foundation

/// An event as returned by `/api/reports/events`, e.g. a geofence crossing.
public struct TraccarEvent: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let type: String
    public let eventTime: Date
    public let deviceId: Int
    public let geofenceId: Int?

    public init(id: Int, type: String, eventTime: Date, deviceId: Int, geofenceId: Int?) {
        self.id = id
        self.type = type
        self.eventTime = eventTime
        self.deviceId = deviceId
        self.geofenceId = geofenceId
    }
}

extension TraccarEvent {
    public enum EventType {
        public static let geofenceEnter = "geofenceEnter"
        public static let geofenceExit = "geofenceExit"
    }
}
