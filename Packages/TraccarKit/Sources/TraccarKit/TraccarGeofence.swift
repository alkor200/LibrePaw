import Foundation

/// A geofence as returned by `/api/geofences`.
public struct TraccarGeofence: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    /// The geofence shape encoded as WKT (e.g. `CIRCLE (lon lat, radiusMeters)`
    /// for a circle — see ``TraccarGeofenceArea``).
    public let area: String
    public let attributes: [String: JSONValue]

    public init(id: Int, name: String, area: String, attributes: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.area = area
        self.attributes = attributes
    }
}

/// A new geofence to create via `POST /api/geofences`.
struct NewTraccarGeofence: Encodable, Sendable {
    let name: String
    let area: String
    let attributes: [String: Bool]
}

/// An update to an existing geofence via `PUT /api/geofences/{id}`.
struct UpdatedTraccarGeofence: Encodable, Sendable {
    let id: Int
    let name: String
    let area: String
    let attributes: [String: Bool]
}

/// Links a device to a geofence via `POST /api/permissions`.
struct GeofenceDevicePermission: Encodable, Sendable {
    let deviceId: Int
    let geofenceId: Int
}

/// Builds and parses the WKT `CIRCLE (longitude latitude, radiusMeters)`
/// format Traccar uses for circular geofences — verified against a live
/// server (see ADR-0014): coordinates are longitude first, then latitude,
/// matching WKT's conventional (X, Y) axis order.
public enum TraccarGeofenceArea {
    public static func circleWKT(centerLatitude: Double, centerLongitude: Double, radiusMeters: Double) -> String {
        "CIRCLE (\(centerLongitude) \(centerLatitude), \(radiusMeters))"
    }

    public static func parseCircle(_ wkt: String) -> (latitude: Double, longitude: Double, radiusMeters: Double)? {
        guard wkt.hasPrefix("CIRCLE"),
              let openParen = wkt.firstIndex(of: "("),
              let closeParen = wkt.lastIndex(of: ")"),
              openParen < closeParen else {
            return nil
        }

        let inner = wkt[wkt.index(after: openParen)..<closeParen]
        let parts = inner.split(separator: ",")
        guard parts.count == 2 else { return nil }

        let coordinateParts = parts[0].trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard coordinateParts.count == 2,
              let longitude = Double(coordinateParts[0]),
              let latitude = Double(coordinateParts[1]),
              let radius = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        return (latitude: latitude, longitude: longitude, radiusMeters: radius)
    }
}
