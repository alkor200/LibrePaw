import Foundation

/// A geofence as returned by `/api/geofences`.
public struct TraccarGeofence: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    /// The geofence shape encoded as WKT (e.g. `CIRCLE (lat lon, radiusMeters)`
    /// for a circle, see ``TraccarGeofenceArea``).
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
    let attributes: [String: JSONValue]
}

/// An update to an existing geofence via `PUT /api/geofences/{id}`.
struct UpdatedTraccarGeofence: Encodable, Sendable {
    let id: Int
    let name: String
    let area: String
    let attributes: [String: JSONValue]
}

/// Links a device to a geofence via `POST /api/permissions`. This alone does
/// **not** make the geofence visible to any user, see
/// ``UserGeofencePermission`` and ADR-0017.
struct GeofenceDevicePermission: Encodable, Sendable {
    let deviceId: Int
    let geofenceId: Int
}

/// Links a user to a geofence via `POST /api/permissions`, required, on top
/// of ``GeofenceDevicePermission``, for that user to see or manage the
/// geofence at all (confirmed against Traccar's own docs/source; see
/// ADR-0017).
struct UserGeofencePermission: Encodable, Sendable {
    let userId: Int
    let geofenceId: Int
}

/// One permission link as returned by `GET /api/permissions`. Traccar's
/// `Permission` object can carry many different `*Id` fields depending on
/// which two were queried (userId+deviceId, userId+geofenceId, etc.), only
/// the ones LibrePaw reads are modeled here, the rest decode as absent.
///
/// Unlike every other Traccar JSON response (camelCase, e.g. `TraccarDevice`'s
/// `groupId`), confirmed against a live server that `/api/permissions`
/// specifically returns this object's keys in **UPPERCASE**
/// (`{"USERID":4,"DEVICEID":3}`), evidently raw SQL column names leaking
/// through rather than going through normal POJO serialization. Decoding
/// with the usual camelCase keys doesn't throw, `Int?` properties that
/// don't match just decode as `nil`, so this silently returned an empty
/// result from every caller instead of an error, which is a much nastier
/// failure mode to catch. Explicit `CodingKeys` below map to the real keys.
public struct TraccarPermission: Decodable, Sendable, Equatable {
    public let userId: Int?
    public let deviceId: Int?
    public let geofenceId: Int?

    private enum CodingKeys: String, CodingKey {
        case userId = "USERID"
        case deviceId = "DEVICEID"
        case geofenceId = "GEOFENCEID"
    }

    public init(userId: Int?, deviceId: Int?, geofenceId: Int?) {
        self.userId = userId
        self.deviceId = deviceId
        self.geofenceId = geofenceId
    }
}

/// Builds and parses the WKT `CIRCLE (lat lon, radiusMeters)` format Traccar
/// uses for circular geofences.
///
/// This is **latitude first**, unlike standard WKT's (X, Y) =
/// (longitude, latitude) axis order, confirmed by reading Traccar's own
/// `GeofenceCircle.fromWkt`/`toWkt` source directly (`centerLatitude` is
/// parsed from the first token, `centerLongitude` from the second) after an
/// earlier version of this code got the order backwards. That bug shipped
/// silently: writing and reading it back with the same (wrong) convention
/// round-trips perfectly in isolation, so the mistake only surfaced when a
/// geofence built this way was tested against Traccar's actual geofence
/// evaluation and never matched any position near the intended location.
/// See ADR-0014.
public enum TraccarGeofenceArea {
    public static func circleWKT(centerLatitude: Double, centerLongitude: Double, radiusMeters: Double) -> String {
        "CIRCLE (\(centerLatitude) \(centerLongitude), \(radiusMeters))"
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
              let latitude = Double(coordinateParts[0]),
              let longitude = Double(coordinateParts[1]),
              let radius = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        return (latitude: latitude, longitude: longitude, radiusMeters: radius)
    }
}
