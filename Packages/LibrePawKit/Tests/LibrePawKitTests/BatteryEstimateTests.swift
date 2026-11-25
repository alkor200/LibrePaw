import Foundation
import Testing
@testable import LibrePawKit

@Suite("BatteryEstimate")
struct BatteryEstimateTests {
    @Test("Follows the measured MT710 discharge, not a generic Li-ion table")
    func followsMeasuredCurve() {
        #expect(BatteryEstimate.percent(forVoltage: 3.70) == 48)
        #expect(abs(BatteryEstimate.percent(forVoltage: 3.711) - 48.88) < 0.01)
        #expect(BatteryEstimate.percent(forVoltage: 3.90) == 70)
    }

    @Test("Clamps outside the measured range")
    func clamps() {
        #expect(BatteryEstimate.percent(forVoltage: 4.2) == 100)
        #expect(BatteryEstimate.percent(forVoltage: 3.1) == 0)
        #expect(BatteryEstimate.percent(forVoltage: 3.15) == 0)
        #expect(BatteryEstimate.percent(forVoltage: 3.5) == 3)
    }

    @Test("A reported percentage wins over the voltage, a voltage alone is an estimate")
    func reportedWinsOverEstimate() {
        func position(percent: Double?, volts: Double?) -> PetPosition {
            PetPosition(id: 1, petID: 1, coordinate: Coordinate(latitude: 0, longitude: 0), recordedAt: .now,
                        speedKilometersPerHour: 0, address: nil, batteryLevelPercent: percent, batteryVoltage: volts)
        }
        #expect(position(percent: 76, volts: 3.7).battery == BatteryReading(percent: 76, isEstimate: false))
        #expect(position(percent: nil, volts: 3.7).battery == BatteryReading(percent: 48, isEstimate: true))
        #expect(position(percent: nil, volts: nil).battery == nil)
    }
}
