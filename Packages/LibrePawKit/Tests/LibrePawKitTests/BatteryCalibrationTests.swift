import Foundation
import Testing
@testable import LibrePawKit

@Suite("BatteryCalibration")
struct BatteryCalibrationTests {
    private let start = Date(timeIntervalSince1970: 1_794_000_000)

    /// A 100-hour discharge from `full` to `empty`, one report every 30
    /// minutes, voltage falling linearly with time.
    private func linearDischarge(from offsetHours: Double = 0, full: Double = 4.1, empty: Double = 3.2) -> [BatteryCalibration.Sample] {
        (0...200).map { step in
            let fraction = Double(step) / 200
            return BatteryCalibration.Sample(
                time: start.addingTimeInterval((offsetHours + fraction * 100) * 3_600),
                volts: full - fraction * (full - empty)
            )
        }
    }

    @Test("A linear discharge yields a linear curve from empty to full")
    func linearDischargeYieldsLinearCurve() throws {
        let curve = try #require(BatteryCalibration.curve(from: linearDischarge()))

        #expect(curve.cycleCount == 1)
        let runtime = curve.averageRuntime ?? -1
        #expect(abs(runtime - 100 * 3_600) < 1, "got \(runtime / 3_600) h")
        #expect(curve.percent(forVoltage: 3.2) == 0)
        #expect(curve.percent(forVoltage: 4.1) == 100)
        // Half way in voltage is half way in runtime here.
        #expect(abs(curve.percent(forVoltage: 3.65) - 50) < 2)
    }

    @Test("Without a full discharge on record there's nothing to learn")
    func partialDischargesAreIgnored() {
        // Charged again at 3.6 V, never ran down.
        let partial = linearDischarge(full: 4.1, empty: 3.6)
        // Charged again, but only part way (below `fullVoltage`), then run
        // down to empty.
        let halfStart = linearDischarge(from: 200, full: 3.95, empty: 3.2)

        #expect(BatteryCalibration.curve(from: partial + halfStart) == nil)
    }

    @Test("Each charge splits the history, several full discharges are averaged")
    func severalDischargesAreAveraged() throws {
        let curve = try #require(BatteryCalibration.curve(from: linearDischarge() + linearDischarge(from: 150)))

        #expect(curve.cycleCount == 2)
        #expect(abs(curve.percent(forVoltage: 3.65) - 50) < 2)
    }

    @Test("A voltage recovering while idle doesn't count as charge coming back")
    func recoveryUsesRunningMinimum() throws {
        var samples = linearDischarge()
        // A brief rebound mid-way, below the charge threshold.
        samples[100] = BatteryCalibration.Sample(time: samples[100].time, volts: samples[100].volts + 0.2)

        let curve = try #require(BatteryCalibration.curve(from: samples))

        #expect(curve.cycleCount == 1)
        #expect(abs(curve.percent(forVoltage: 3.65) - 50) < 2)
    }

    @Test("A reported percentage wins, a voltage alone is estimated with the given curve")
    func positionUsesCurve() throws {
        let curve = try #require(BatteryCalibration.curve(from: linearDischarge()))
        func position(percent: Double?, volts: Double?) -> PetPosition {
            PetPosition(id: 1, petID: 1, coordinate: Coordinate(latitude: 0, longitude: 0), recordedAt: .now,
                        speedKilometersPerHour: 0, address: nil, batteryLevelPercent: percent, batteryVoltage: volts)
        }

        #expect(position(percent: 76, volts: 3.65).battery(using: curve) == BatteryReading(percent: 76, isEstimate: false))
        #expect(position(percent: nil, volts: 3.2).battery(using: curve) == BatteryReading(percent: 0, isEstimate: true))
        #expect(position(percent: nil, volts: nil).battery(using: curve) == nil)
    }

    @Test("The generic fallback clamps outside its range")
    func genericClamps() {
        #expect(BatteryCurve.generic.percent(forVoltage: 4.5) == 100)
        #expect(BatteryCurve.generic.percent(forVoltage: 3.0) == 0)
    }
}
