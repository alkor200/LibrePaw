import Foundation
import LibrePawKit

/// Which days the Statistics screen covers.
enum StatsRange: Hashable, CaseIterable, Identifiable {
    case week, month, quarter, all

    var id: Self { self }

    var label: String {
        switch self {
        case .week: localized("7 Days")
        case .month: localized("30 Days")
        case .quarter: localized("90 Days")
        case .all: localized("All")
        }
    }

    /// The first day included, `nil` for "since the first walk".
    func firstDay(now: Date = .now, calendar: Calendar = .current) -> Date? {
        let days: Int? = switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
        return days.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: calendar.startOfDay(for: now)) }
    }
}

/// Loads everything the Statistics screen needs: every excursion on record
/// (served from the excursions cache, see ADR-0026) for the walk statistics,
/// and the last two weeks of battery readings for the battery chart.
@Observable
@MainActor
final class StatsViewModel {
    let pet: Pet
    var range: StatsRange = .all {
        didSet { recompute() }
    }

    private(set) var statistics: ExcursionStatistics?
    private(set) var batteryCurve: BatteryCurve = .generic
    private(set) var batteryHistory: [BatteryPoint] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var isRecalculating = false
    var recalculateErrorMessage: String?

    /// One battery level on the chart, at most one per hour.
    struct BatteryPoint: Identifiable, Hashable {
        let time: Date
        let percent: Double
        var id: Date { time }
    }

    /// How far back the battery chart reaches. Unlike excursions, raw
    /// positions of a range still running aren't cached, so this stays a
    /// couple of weeks rather than everything.
    static let batteryHistoryDays = 14

    private var excursions: [Excursion] = []
    private let petRepository: PetRepository

    init(pet: Pet, petRepository: PetRepository) {
        self.pet = pet
        self.petRepository = petRepository
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let battery: Void = loadBattery()
        do {
            excursions = try await petRepository.fetchExcursions(forPetID: pet.id, from: .distantPast, to: .now)
            recompute()
        } catch {
            errorMessage = error.userFacingMessage
        }
        await battery
    }

    /// Recomputes the excursions cache and every statistic from scratch,
    /// see `PetRepository.resetExcursionsCache(forPetID:)`, for recovering
    /// from bad cached data, moved here from Pet Detail's lifetime tiles.
    func recalculate() async {
        isRecalculating = true
        defer { isRecalculating = false }
        do {
            try await petRepository.resetExcursionsCache(forPetID: pet.id)
            try await petRepository.resetLifetimeStats(forPetID: pet.id)
            excursions = try await petRepository.fetchExcursions(forPetID: pet.id, from: .distantPast, to: .now)
            recompute()
        } catch {
            recalculateErrorMessage = error.userFacingMessage
        }
    }

    private func recompute() {
        statistics = ExcursionStatistics(excursions: excursions, from: range.firstDay())
    }

    /// Best-effort, the battery chart simply stays empty without it.
    private func loadBattery() async {
        let curve = await petRepository.batteryCurve(forPetID: pet.id)
        batteryCurve = curve
        let now = Date.now
        guard let from = Calendar.current.date(byAdding: .day, value: -Self.batteryHistoryDays, to: now),
              let positions = try? await petRepository.fetchTrail(forPetID: pet.id, from: from, to: now) else { return }

        // A reported percentage as is, a voltage smoothed first (see
        // `BatteryCalibration.smoothed`), a single report's voltage sags
        // whenever the tracker is busy.
        let voltages = positions.compactMap { position in
            position.batteryLevelPercent == nil
                ? position.batteryVoltage.map { BatteryCalibration.Sample(time: position.recordedAt, volts: $0) }
                : nil
        }
        let smoothedVolts = Dictionary(
            BatteryCalibration.smoothed(voltages).map { ($0.time, $0.volts) },
            uniquingKeysWith: { _, latest in latest }
        )
        var latestPerHour: [Date: BatteryPoint] = [:]
        for position in positions {
            let percent: Double
            if let reported = position.batteryLevelPercent {
                percent = reported
            } else if let volts = smoothedVolts[position.recordedAt] {
                percent = curve.percent(forVoltage: volts)
            } else {
                continue
            }
            let hour = Calendar.current.dateInterval(of: .hour, for: position.recordedAt)?.start ?? position.recordedAt
            latestPerHour[hour] = BatteryPoint(time: hour, percent: percent)
        }
        batteryHistory = latestPerHour.values.sorted { $0.time < $1.time }
    }

    /// Whether the levels on the battery chart are estimated from the
    /// voltage rather than reported by the tracker.
    var batteryIsEstimated: Bool {
        pet.lastPosition?.batteryLevelPercent == nil
    }
}
