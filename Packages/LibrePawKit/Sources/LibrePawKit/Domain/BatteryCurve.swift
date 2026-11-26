import Foundation

/// A battery level to show, see ``PetPosition/battery(using:)``.
public struct BatteryReading: Sendable, Hashable {
    /// 0 to 100.
    public let percent: Double
    /// `true` when derived from the voltage rather than reported by the
    /// tracker, the app shows it as approximate.
    public let isEstimate: Bool

    public init(percent: Double, isEstimate: Bool) {
        self.percent = percent
        self.isEstimate = isEstimate
    }
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

    /// Ascending by voltage, percentages never decreasing. A percentage is
    /// the share of a charge's *active* time still left, see
    /// ``BatteryCalibration``.
    public let points: [Point]
    /// How many full discharges this curve was learned from, 0 for
    /// ``generic``.
    public let cycleCount: Int
    /// How much active time (the tracker awake and reporting, i.e. mostly
    /// the pet being out, see ``BatteryCalibration/activeGap``) a full
    /// charge lasted on average across those discharges, `nil` for
    /// ``generic``.
    public let averageActiveRuntime: TimeInterval?

    public init(points: [Point], cycleCount: Int, averageActiveRuntime: TimeInterval? = nil) {
        self.points = points
        self.cycleCount = cycleCount
        self.averageActiveRuntime = averageActiveRuntime
    }

    /// Roughly how much more active time the battery has at `volts`, `nil`
    /// for ``generic``, which knows nothing about this tracker's runtime.
    public func activeTimeLeft(forVoltage volts: Double) -> TimeInterval? {
        activeTimeLeft(atPercent: percent(forVoltage: volts))
    }

    public func activeTimeLeft(atPercent percent: Double) -> TimeInterval? {
        averageActiveRuntime.map { $0 * percent / 100 }
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
/// The voltage a tracker reports is noisy: it sags by up to 0.4 V for a
/// while whenever the modem or GPS draws current and recovers after,
/// confirmed on a real MT710 (3.80, 3.37, then 3.76 V within an hour). So
/// the history is first split into discharges at every charge, counting
/// only a jump of more than ``chargeJump`` that *holds* (the median of the
/// next ``chargeConfirmationWindow`` stays that far above the median of
/// the one before, a sag recovering doesn't), and each discharge is
/// smoothed with a running median over ``smoothingWindow`` (see
/// ``smoothed(_:)``).
///
/// Only full discharges are learned from: starting at least
/// ``fullVoltage`` and running down to ``emptyVoltage`` or below (raw),
/// i.e. until the tracker switched itself off, the last report that low
/// being its end. For each, every voltage on a fixed grid is mapped to the
/// share of that discharge's *active* time still left once the smoothed
/// voltage first fell to it. Several discharges are averaged, the lowest
/// smoothed voltages reached become 0 % and the starting voltages 100 %.
///
/// Active time, not time on the clock: a tracker like the MT710 goes to
/// standby at home and reports every few seconds while out, and nearly all
/// of a charge goes to the latter. On a real MT710 two full charges lasted
/// 118 and 137 hours on the clock but 9.8 and 9.9 hours of active time,
/// and at the same voltage both had about the same active time left. So
/// the level stays put while the pet is home and falls while it's out,
/// and what's left reads as "enough for about so many hours out".
public enum BatteryCalibration {
    public struct Sample: Sendable, Hashable {
        public let time: Date
        public let volts: Double

        public init(time: Date, volts: Double) {
            self.time = time
            self.volts = volts
        }
    }

    /// A gap between two reports up to this long counts as active time,
    /// longer ones as standby.
    public static let activeGap: TimeInterval = 30 * 60
    static let chargeJump = 0.3
    static let chargeConfirmationWindow: TimeInterval = 3 * 3_600
    /// Picked against two real MT710 discharges: shorter windows let single
    /// sags through (the level hopping up by up to 8 points), longer ones
    /// don't track a straight line any better and lag more.
    public static let smoothingWindow: TimeInterval = 9 * 3_600
    static let fullVoltage = 4.0
    static let emptyVoltage = 3.35
    /// Shorter discharges are noise, not a real charge running out.
    static let minimumRuntime: TimeInterval = 6 * 3_600
    static let minimumActiveRuntime: TimeInterval = 3_600
    static let gridStep = 0.05

    /// `nil` without a single full discharge in `samples`.
    public static func curve(from samples: [Sample]) -> BatteryCurve? {
        var fractionsByGridIndex: [Int: [Double]] = [:]
        var fullVoltages: [Double] = []
        var emptyVoltages: [Double] = []
        var runtimes: [TimeInterval] = []
        for discharge in discharges(samples) {
            // The last report at or below empty, not the lowest one, a sag
            // shortly before can dip lower than where the tracker switched
            // itself off.
            guard let start = discharge.first, start.volts >= fullVoltage,
                  let end = discharge.last(where: { $0.volts <= emptyVoltage }) else { continue }
            guard end.time.timeIntervalSince(start.time) >= minimumRuntime,
                  let endIndex = discharge.lastIndex(of: end) else { continue }
            let activeClock = activeTime(discharge)
            let runtime = activeClock[endIndex]
            guard runtime >= minimumActiveRuntime else { continue }

            var runningMin = Double.infinity
            var firstActiveTimeAtOrBelow: [Int: TimeInterval] = [:]
            for (index, sample) in smoothedDischarge(discharge).enumerated() where index <= endIndex {
                runningMin = min(runningMin, sample.volts)
                for gridIndex in gridIndices(downTo: runningMin, below: start.volts) where firstActiveTimeAtOrBelow[gridIndex] == nil {
                    firstActiveTimeAtOrBelow[gridIndex] = activeClock[index]
                }
            }
            fullVoltages.append(start.volts)
            emptyVoltages.append(runningMin)
            runtimes.append(runtime)
            for (gridIndex, activeTime) in firstActiveTimeAtOrBelow {
                fractionsByGridIndex[gridIndex, default: []].append((runtime - activeTime) / runtime)
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
            averageActiveRuntime: runtimes.reduce(0, +) / Double(runtimes.count)
        )
    }

    /// The active time elapsed at each sample since the discharge's first,
    /// gaps up to ``activeGap`` counted, longer ones (standby) not.
    private static func activeTime(_ discharge: [Sample]) -> [TimeInterval] {
        var elapsed: TimeInterval = 0
        var clock: [TimeInterval] = [0]
        for (previous, sample) in zip(discharge, discharge.dropFirst()) {
            let gap = sample.time.timeIntervalSince(previous.time)
            if gap <= activeGap { elapsed += gap }
            clock.append(elapsed)
        }
        return clock
    }

    /// `samples` with each voltage replaced by the median of the samples in
    /// the ``smoothingWindow`` up to it, never reaching back across a
    /// charge. What a level should be read from, a single report's voltage
    /// says more about what the tracker was doing at that moment than about
    /// its charge.
    public static func smoothed(_ samples: [Sample]) -> [Sample] {
        discharges(samples).flatMap(smoothedDischarge)
    }

    /// Split at every charge, oldest first.
    static func discharges(_ samples: [Sample]) -> [[Sample]] {
        let sorted = samples.sorted { $0.time < $1.time }
        var discharges: [[Sample]] = []
        var current: [Sample] = []
        for (index, sample) in sorted.enumerated() {
            if let previous = current.last, sample.volts - previous.volts > chargeJump, isCharge(at: index, in: sorted) {
                discharges.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { discharges.append(current) }
        return discharges
    }

    /// Whether the jump up to `sorted[index]` holds rather than being a
    /// sag recovering.
    private static func isCharge(at index: Int, in sorted: [Sample]) -> Bool {
        let time = sorted[index].time
        // At least the report right before, a tracker usually charges
        // after it ran empty and stayed off for a while.
        var before = sorted[..<index].reversed().prefix { time.timeIntervalSince($0.time) <= chargeConfirmationWindow }.map(\.volts)
        if before.isEmpty { before = [sorted[index - 1].volts] }
        let after = sorted[index...].prefix { $0.time.timeIntervalSince(time) <= chargeConfirmationWindow }.map(\.volts)
        guard let medianBefore = median(before), let medianAfter = median(after) else { return false }
        return medianAfter - medianBefore > chargeJump
    }

    private static func smoothedDischarge(_ discharge: [Sample]) -> [Sample] {
        var windowStart = 0
        return discharge.enumerated().map { index, sample in
            while sample.time.timeIntervalSince(discharge[windowStart].time) > smoothingWindow {
                windowStart += 1
            }
            let volts = median(discharge[windowStart...index].map(\.volts)) ?? sample.volts
            return Sample(time: sample.time, volts: volts)
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Grid voltages (as multiples of `gridStep`) a running minimum of
    /// `volts` has reached, below the discharge's starting voltage.
    private static func gridIndices(downTo volts: Double, below start: Double) -> [Int] {
        let lowest = Int((volts / gridStep).rounded(.up))
        let highest = Int((start / gridStep).rounded(.down))
        return lowest <= highest ? Array(lowest...highest) : []
    }
}
