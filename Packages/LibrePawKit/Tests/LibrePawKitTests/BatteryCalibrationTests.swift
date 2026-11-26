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

    /// The level shown over `samples` with `curve`, read from the smoothed
    /// voltage like the app does, against how much of the runtime is left.
    private func worstDeviationFromStraightLine(_ samples: [BatteryCalibration.Sample], curve: BatteryCurve) -> Double {
        let smoothed = BatteryCalibration.smoothed(samples)
        guard let first = smoothed.first, let last = smoothed.last else { return .infinity }
        let runtime = last.time.timeIntervalSince(first.time)
        return smoothed.map { sample in
            let left = 100 * (1 - sample.time.timeIntervalSince(first.time) / runtime)
            return abs(curve.percent(forVoltage: sample.volts) - left)
        }.max() ?? .infinity
    }

    @Test("A linear discharge yields a curve the level falls evenly with")
    func linearDischargeYieldsLinearCurve() throws {
        let samples = linearDischarge()
        let curve = try #require(BatteryCalibration.curve(from: samples))

        #expect(curve.cycleCount == 1)
        let runtime = curve.averageActiveRuntime ?? -1
        #expect(abs(runtime - 100 * 3_600) < 1, "got \(runtime / 3_600) h")
        #expect(curve.percent(forVoltage: 3.0) == 0)
        #expect(curve.percent(forVoltage: 4.1) == 100)
        #expect(worstDeviationFromStraightLine(samples, curve: curve) < 3)
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
        #expect(worstDeviationFromStraightLine(linearDischarge(), curve: curve) < 3)
    }

    @Test("A sag under load that recovers is neither a charge nor the battery running low")
    func sagsAreIgnored() throws {
        var samples = linearDischarge()
        // Like a real MT710: the voltage drops by 0.4 V for an hour while
        // the modem is busy, then comes back. Twice, once early, once late.
        for index in [60, 61, 150, 151] {
            samples[index] = BatteryCalibration.Sample(time: samples[index].time, volts: samples[index].volts - 0.4)
        }

        let curve = try #require(BatteryCalibration.curve(from: samples))

        #expect(curve.cycleCount == 1)
        let runtime = curve.averageActiveRuntime ?? -1
        #expect(abs(runtime - 100 * 3_600) < 1, "got \(runtime / 3_600) h")
        #expect(worstDeviationFromStraightLine(samples, curve: curve) < 3)
        #expect(BatteryCalibration.discharges(samples).count == 1)
    }

    @Test("A charge is measured in active time, hours on standby at home don't count")
    func standbyDoesNotCount() throws {
        // Ten walks of one hour each, a report every 5 minutes, the voltage
        // falling only then, with 11 hours of silence (standby at home)
        // after each.
        var samples: [BatteryCalibration.Sample] = []
        var time = start
        var volts = 4.1
        for _ in 0..<10 {
            for _ in 0...12 {
                samples.append(BatteryCalibration.Sample(time: time, volts: volts))
                time = time.addingTimeInterval(5 * 60)
                volts -= 0.9 / 130
            }
            time = time.addingTimeInterval(11 * 3_600)
        }

        let curve = try #require(BatteryCalibration.curve(from: samples))

        let runtime = try #require(curve.averageActiveRuntime)
        #expect(abs(runtime - 10 * 3_600) < 3_600, "got \(runtime / 3_600) h")
        // Half way down in voltage, half of the walking time is left, not
        // half of the five and a half days on the clock.
        let left = try #require(curve.activeTimeLeft(forVoltage: 3.65))
        #expect(abs(left - 5 * 3_600) < 1.5 * 3_600, "got \(left / 3_600) h")
        #expect(BatteryCurve.generic.activeTimeLeft(forVoltage: 3.8) == nil)
    }

    @Test("Smoothing never reaches back across a charge")
    func smoothingRestartsAtCharge() {
        let samples = linearDischarge() + linearDischarge(from: 150)
        let smoothed = BatteryCalibration.smoothed(samples)

        #expect(smoothed.count == samples.count)
        // The first report after charging reads full, not a median with
        // the empty battery before.
        #expect(smoothed[201].volts == 4.1)
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
