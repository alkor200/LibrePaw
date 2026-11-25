import Foundation

/// A battery level to show, see ``PetPosition/battery``.
public struct BatteryReading: Sendable, Hashable {
    /// 0 to 100.
    public let percent: Double
    /// `true` when derived from the voltage rather than reported by the
    /// tracker, the app shows it as approximate.
    public let isEstimate: Bool
}

/// Estimates a single-cell lithium battery's remaining charge from its
/// voltage, for trackers that only report that (the Mictrack MT710 over
/// Traccar's `tlt2h` protocol reports `battery` in volts, no percentage).
///
/// The voltage of such a battery isn't linear in its charge: it sits around
/// 3.7 to 3.8 V for most of the time and only drops steeply near the end,
/// and how far depends on the device's load. A generic Li-ion table puts
/// 3.71 V at about 15 %, far too pessimistic for this tracker. The points
/// below come from a full real discharge instead: an MT710 running from
/// 4.09 V down to empty in 137 hours (2026-11-15 to 21), each voltage
/// mapped to the share of that runtime still left once it was first
/// reached. The empty end comes from all three discharges on record: the
/// tracker kept reporting down to 3.11 to 3.20 V before it switched off,
/// and below 3.5 V had anywhere from 44 minutes (out walking) to about 9
/// hours (asleep at home) left, a few percent of a full charge at most.
/// Interpolated linearly in between, clamped to 0 and 100.
public enum BatteryEstimate {
    static let curve: [(volts: Double, percent: Double)] = [
        (3.15, 0),
        (3.50, 3),
        (3.60, 12),
        (3.70, 48),
        (3.80, 56),
        (3.90, 70),
        (4.10, 100)
    ]

    public static func percent(forVoltage volts: Double) -> Double {
        guard let first = curve.first, let last = curve.last else { return 0 }
        if volts <= first.volts { return first.percent }
        if volts >= last.volts { return last.percent }
        for (lower, upper) in zip(curve, curve.dropFirst()) where volts <= upper.volts {
            let fraction = (volts - lower.volts) / (upper.volts - lower.volts)
            return lower.percent + fraction * (upper.percent - lower.percent)
        }
        return last.percent
    }
}
