import Foundation

/// A battery level to show, see ``PetPosition/battery(using:)``.
public struct BatteryReading: Sendable, Hashable {
    /// 0 to 100.
    public let percent: Double
    /// `true` when derived from the voltage rather than reported by the
    /// tracker, the app shows it as approximate.
    public let isEstimate: Bool
}

/// Maps a single-cell lithium battery's voltage to its remaining charge,
/// for trackers that report only the voltage (the Mictrack MT710 over
/// Traccar's `tlt2h` protocol reports `battery` in volts, no percentage).
///
/// Such a battery's voltage isn't linear in its charge, it sits around 3.7
/// to 3.8 V for most of the time and only drops steeply near the end, by
/// how much depending on the device and its load. So each tracker gets its
/// own curve, learned from its own voltage history by
/// ``BatteryCalibration``, and only falls back to ``generic`` until it has
/// recorded a full discharge.
public struct BatteryCurve: Sendable, Hashable, Codable {
    public struct Point: Sendable, Hashable, Codable {
        public let volts: Double
        public let percent: Double
    }

    /// Ascending by voltage, percentages never decreasing.
    public let points: [Point]
    /// How many full discharges this curve was learned from, 0 for
    /// ``generic``.
    public let cycleCount: Int
    /// How long a full charge lasted on average across those discharges,
    /// `nil` for ``generic``.
    public let averageRuntime: TimeInterval?

    public init(points: [Point], cycleCount: Int, averageRuntime: TimeInterval? = nil) {
        self.points = points
        self.cycleCount = cycleCount
        self.averageRuntime = averageRuntime
    }

    /// A typical single-cell Li-ion discharge, for a tracker without a full
    /// discharge on record yet.
    public static let generic = BatteryCurve(points: [
        Point(volts: 3.30, percent: 0),
        Point(volts: 3.50, percent: 5),
        Point(volts: 3.60, percent: 15),
        Point(volts: 3.70, percent: 30),
        Point(volts: 3.80, percent: 50),
        Point(volts: 3.90, percent: 65),
        Point(volts: 4.00, percent: 80),
        Point(volts: 4.10, percent: 90),
        Point(volts: 4.20, percent: 100)
    ], cycleCount: 0)

    /// Interpolated linearly between points, clamped to 0 and 100.
    public func percent(forVoltage volts: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if volts <= first.volts { return first.percent }
        if volts >= last.volts { return last.percent }
        for (lower, upper) in zip(points, points.dropFirst()) where volts <= upper.volts {
            guard upper.volts > lower.volts else { continue }
            let fraction = (volts - lower.volts) / (upper.volts - lower.volts)
            return min(100, max(0, lower.percent + fraction * (upper.percent - lower.percent)))
        }
        return last.percent
    }
}

/// Learns a tracker's ``BatteryCurve`` from its own voltage history.
///
/// Splits the history into discharges at every charge (the voltage
/// jumping up by more than ``chargeJump`` between two reports) and keeps
/// only full ones: starting at least ``fullVoltage`` and running down to
/// ``emptyVoltage`` or below, i.e. until the tracker switched itself off.
/// For each, every voltage on a fixed grid is mapped to the share of that
/// discharge's runtime still left once the voltage first fell to it, the
/// running minimum, since the voltage recovers a little whenever the
/// tracker idles. Several discharges are averaged, the lowest voltages
/// reached become 0 % and the starting voltages 100 %.
///
/// Measured on time rather than energy, so the result reads as "how much
/// of a charge's runtime is left", which is what a pet owner wants to know.
public enum BatteryCalibration {
    public struct Sample: Sendable, Hashable {
        public let time: Date
        public let volts: Double

        public init(time: Date, volts: Double) {
            self.time = time
            self.volts = volts
        }
    }

    static let chargeJump = 0.3
    static let fullVoltage = 4.0
    static let emptyVoltage = 3.35
    /// Shorter discharges are noise, not a real charge running out.
    static let minimumRuntime: TimeInterval = 6 * 3_600
    static let gridStep = 0.05

    /// `nil` without a single full discharge in `samples`.
    public static func curve(from samples: [Sample]) -> BatteryCurve? {
        let sorted = samples.sorted { $0.time < $1.time }
        var discharges: [[Sample]] = []
        var current: [Sample] = []
        for sample in sorted {
            if let previous = current.last, sample.volts - previous.volts > chargeJump {
                discharges.append(current)
                current = []
            }
            current.append(sample)
        }
        discharges.append(current)

        var fractionsByGridIndex: [Int: [Double]] = [:]
        var fullVoltages: [Double] = []
        var emptyVoltages: [Double] = []
        var runtimes: [TimeInterval] = []
        for discharge in discharges {
            guard let start = discharge.first, start.volts >= fullVoltage,
                  let end = discharge.min(by: { $0.volts < $1.volts }), end.volts <= emptyVoltage else { continue }
            let runtime = end.time.timeIntervalSince(start.time)
            guard runtime >= minimumRuntime else { continue }
            fullVoltages.append(start.volts)
            emptyVoltages.append(end.volts)
            runtimes.append(runtime)

            var runningMin = Double.infinity
            var firstTimeAtOrBelow: [Int: Date] = [:]
            for sample in discharge where sample.time <= end.time {
                runningMin = min(runningMin, sample.volts)
                for index in gridIndices(downTo: runningMin, below: start.volts) where firstTimeAtOrBelow[index] == nil {
                    firstTimeAtOrBelow[index] = sample.time
                }
            }
            for (index, time) in firstTimeAtOrBelow {
                fractionsByGridIndex[index, default: []].append(end.time.timeIntervalSince(time) / runtime)
            }
        }
        guard !emptyVoltages.isEmpty else { return nil }

        let empty = emptyVoltages.reduce(0, +) / Double(emptyVoltages.count)
        let full = fullVoltages.reduce(0, +) / Double(fullVoltages.count)
        var points = [BatteryCurve.Point(volts: empty, percent: 0)]
        for index in fractionsByGridIndex.keys.sorted() {
            let volts = Double(index) * gridStep
            guard volts > empty, volts < full, let fractions = fractionsByGridIndex[index] else { continue }
            let percent = 100 * fractions.reduce(0, +) / Double(fractions.count)
            // Never below a lower voltage's percentage, averaging several
            // discharges could otherwise make the curve dip.
            points.append(BatteryCurve.Point(volts: volts, percent: max(percent, points.last?.percent ?? 0)))
        }
        points.append(BatteryCurve.Point(volts: full, percent: 100))
        return BatteryCurve(
            points: points,
            cycleCount: emptyVoltages.count,
            averageRuntime: runtimes.reduce(0, +) / Double(runtimes.count)
        )
    }

    /// Grid voltages (as multiples of `gridStep`) a running minimum of
    /// `volts` has reached, below the discharge's starting voltage.
    private static func gridIndices(downTo volts: Double, below start: Double) -> [Int] {
        let lowest = Int((volts / gridStep).rounded(.up))
        let highest = Int((start / gridStep).rounded(.down))
        return lowest <= highest ? Array(lowest...highest) : []
    }
}
