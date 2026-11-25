import Foundation

/// A geographic coordinate, independent of any mapping framework so that
/// `LibrePawKit` does not need to import MapKit/CoreLocation.
public struct Coordinate: Sendable, Hashable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// One GPS fix for a pet.
public struct PetPosition: Identifiable, Sendable, Hashable, Codable {
    public let id: Int
    public let petID: Int
    public let coordinate: Coordinate
    public let recordedAt: Date
    public let speedKilometersPerHour: Double
    public let address: String?
    /// The tracker's own reported battery percentage, if it reports one.
    public let batteryLevelPercent: Double?
    /// The tracker's reported battery voltage, if it reports one.
    public let batteryVoltage: Double?

    /// What to show for the battery: the reported percentage when there is
    /// one, otherwise one estimated from `batteryVoltage` (see
    /// ``BatteryEstimate``), flagged as such.
    public var battery: BatteryReading? {
        if let batteryLevelPercent {
            return BatteryReading(percent: batteryLevelPercent, isEstimate: false)
        }
        return batteryVoltage.map { BatteryReading(percent: BatteryEstimate.percent(forVoltage: $0), isEstimate: true) }
    }

    public init(
        id: Int,
        petID: Int,
        coordinate: Coordinate,
        recordedAt: Date,
        speedKilometersPerHour: Double,
        address: String?,
        batteryLevelPercent: Double?,
        batteryVoltage: Double? = nil
    ) {
        self.id = id
        self.petID = petID
        self.coordinate = coordinate
        self.recordedAt = recordedAt
        self.speedKilometersPerHour = speedKilometersPerHour
        self.address = address
        self.batteryLevelPercent = batteryLevelPercent
        self.batteryVoltage = batteryVoltage
    }
}
