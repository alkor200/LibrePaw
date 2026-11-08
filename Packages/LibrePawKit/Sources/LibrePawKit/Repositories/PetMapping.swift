import Foundation
import TraccarKit

/// Maps Traccar's wire-format DTOs onto LibrePaw's own domain models.
/// This is the one place in the codebase allowed to know both vocabularies.
enum PetMapping {
    static func pet(from device: TraccarDevice, latestPosition: TraccarPosition?, serverURL: URL) -> Pet {
        Pet(
            id: device.id,
            name: device.name,
            species: device.category,
            status: status(from: device.status),
            lastSeenAt: device.lastUpdate,
            lastPosition: latestPosition.map(position(from:)),
            photoURL: photoURL(for: device, serverURL: serverURL)
        )
    }

    /// Traccar stores an uploaded device photo as a filename in the
    /// `deviceImage` attribute, served back at
    /// `/api/media/<uniqueId>/<filename>` (verified against the Traccar web
    /// client's own source, see ADR-0011).
    private static func photoURL(for device: TraccarDevice, serverURL: URL) -> URL? {
        guard let filename = device.attributes["deviceImage"]?.stringValue, !filename.isEmpty else {
            return nil
        }
        return serverURL
            .appendingPathComponent("api/media")
            .appendingPathComponent(device.uniqueId)
            .appendingPathComponent(filename)
    }

    static func status(from status: TraccarDevice.Status) -> Pet.Status {
        switch status {
        case .online: .online
        case .offline: .offline
        case .unknown: .unknown
        }
    }

    static func position(from position: TraccarPosition) -> PetPosition {
        PetPosition(
            id: position.id,
            petID: position.deviceId,
            coordinate: Coordinate(latitude: position.latitude, longitude: position.longitude),
            recordedAt: position.fixTime,
            speedKilometersPerHour: position.speed * 1.852, // Traccar reports speed in knots.
            address: position.address,
            batteryLevelPercent: position.batteryLevel
        )
    }
}
