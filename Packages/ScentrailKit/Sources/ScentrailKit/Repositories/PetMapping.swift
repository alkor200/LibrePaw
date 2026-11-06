import Foundation
import TraccarKit

/// Maps Traccar's wire-format DTOs onto Scentrail's own domain models.
/// This is the one place in the codebase allowed to know both vocabularies.
enum PetMapping {
    static func pet(from device: TraccarDevice, latestPosition: TraccarPosition?) -> Pet {
        Pet(
            id: device.id,
            name: device.name,
            species: device.category,
            status: status(from: device.status),
            lastSeenAt: device.lastUpdate,
            lastPosition: latestPosition.map(position(from:))
        )
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
