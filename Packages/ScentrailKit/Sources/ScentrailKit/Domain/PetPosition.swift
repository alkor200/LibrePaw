import Foundation

/// A geographic coordinate, independent of any mapping framework so that
/// `ScentrailKit` does not need to import MapKit/CoreLocation.
public struct Coordinate: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// One GPS fix for a pet.
public struct PetPosition: Identifiable, Sendable, Hashable {
    public let id: Int
    public let petID: Int
    public let coordinate: Coordinate
    public let recordedAt: Date
    public let speedKilometersPerHour: Double
    public let address: String?
    public let batteryLevelPercent: Double?

    public init(
        id: Int,
        petID: Int,
        coordinate: Coordinate,
        recordedAt: Date,
        speedKilometersPerHour: Double,
        address: String?,
        batteryLevelPercent: Double?
    ) {
        self.id = id
        self.petID = petID
        self.coordinate = coordinate
        self.recordedAt = recordedAt
        self.speedKilometersPerHour = speedKilometersPerHour
        self.address = address
        self.batteryLevelPercent = batteryLevelPercent
    }
}
