import Foundation

/// One message from Traccar's WebSocket feed (`/api/socket`).
///
/// Verified against a live server: Traccar sends a `positions` array
/// whenever a device reports a new fix, a `devices` array when a device's
/// status changes (e.g. online/offline), and an empty object as a periodic
/// keep-alive - any field may be absent on a given message.
public struct TraccarSocketUpdate: Decodable, Sendable {
    public let devices: [TraccarDevice]?
    public let positions: [TraccarPosition]?
}
