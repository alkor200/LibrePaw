import Foundation
import LibrePawKit

/// How the excursions calendar is zoomed.
enum ExcursionCalendarMode: Hashable, CaseIterable, Identifiable {
    case month, week, day

    var id: Self { self }

    var label: String {
        switch self {
        case .month: localized("Month")
        case .week: localized("Week")
        case .day: localized("Day")
        }
    }

    var component: Calendar.Component {
        switch self {
        case .month: .month
        case .week: .weekOfYear
        case .day: .day
        }
    }
}

/// The excursions as a calendar rather than a list: a month grid, a week
/// of day rows with each excursion on a 24-hour bar, and a single day's
/// timeline. Every excursion on record is loaded at once (served from the
/// excursions cache, see ADR-0026), so moving between months, weeks and
/// days never waits on the server.
@Observable
@MainActor
final class ExcursionsViewModel {
    let pet: Pet
    var mode: ExcursionCalendarMode = .month
    /// The day the calendar is centered on: the shown month or week is
    /// the one containing it, the day view shows it.
    var anchor: Date

    private(set) var excursions: [Excursion] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    /// Looked up alongside the excursions themselves so each excursion can
    /// show e.g. "Home → Cabin" when it started and ended at different
    /// homes (see ADR-0016).
    private var homeNamesByID: [Int: String] = [:]

    private let petRepository: PetRepository
    let calendar: Calendar

    init(pet: Pet, petRepository: PetRepository, now: Date = .now, calendar: Calendar = .current) {
        self.pet = pet
        self.petRepository = petRepository
        self.calendar = calendar
        self.anchor = calendar.startOfDay(for: now)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await performLoad()
    }

    /// Reloads without touching `isLoading`, for `.refreshable`: toggling
    /// it there would swap the calendar for a full-screen `ProgressView`
    /// while the pull-to-refresh gesture is still in progress, tearing
    /// down the scroll view (and the system refresh control's own task with
    /// it). Same fix as `PetListViewModel.refresh()`.
    func refresh() async {
        await performLoad()
    }

    private func performLoad() async {
        errorMessage = nil
        do {
            async let fetchedExcursions = petRepository.fetchExcursions(forPetID: pet.id, from: .distantPast, to: .now)
            async let homes = petRepository.homeGeofences(forPetID: pet.id)
            excursions = try await fetchedExcursions.sorted { $0.startTime < $1.startTime }
            homeNamesByID = Dictionary(uniqueKeysWithValues: try await homes.map { ($0.id, $0.name) })
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.userFacingMessage
        }
    }

    func homeName(forHomeID homeID: Int?) -> String? {
        guard let homeID else { return nil }
        return homeNamesByID[homeID]
    }

    // MARK: - Navigating

    /// One month, week or day back (`-1`) or forward (`1`), by `mode`.
    func step(_ direction: Int) {
        anchor = calendar.date(byAdding: mode.component, value: direction, to: anchor) ?? anchor
    }

    func goToToday(now: Date = .now) {
        anchor = calendar.startOfDay(for: now)
    }

    /// Zooms into one day, e.g. after tapping it in the month or week.
    func show(day: Date) {
        anchor = calendar.startOfDay(for: day)
        mode = .day
    }

    /// The month, week or day currently shown.
    var shownInterval: DateInterval {
        calendar.dateInterval(of: mode.component, for: anchor) ?? DateInterval(start: anchor, duration: 86_400)
    }

    var isShowingToday: Bool {
        shownInterval.contains(.now)
    }

    // MARK: - Days

    /// Every day of the shown month or week, start of day each.
    var shownDays: [Date] {
        days(in: shownInterval)
    }

    /// The month grid: whole weeks covering the shown month, `nil` for the
    /// slots before its first and after its last day.
    var monthGrid: [[Date?]] {
        guard let month = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        let monthDays = days(in: month)
        guard let first = monthDays.first else { return [] }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var slots: [Date?] = Array(repeating: nil, count: leading) + monthDays
        while slots.count % 7 != 0 { slots.append(nil) }
        return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
    }

    private func days(in interval: DateInterval) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Excursions overlapping `day` at all, one that runs past midnight
    /// appears on both days. Oldest first.
    func excursions(on day: Date, now: Date = .now) -> [Excursion] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return excursions.filter { excursion in
            excursion.startTime < interval.end && (excursion.endTime ?? now) > interval.start
        }
    }

    /// Totals for excursions that *started* on `day`, the same attribution
    /// the Statistics screen uses, so a day's numbers match there. Likely
    /// vehicle trips aren't counted, same as everywhere else.
    func totals(on day: Date, now: Date = .now) -> DayTotals {
        totals(of: excursions.filter { calendar.isDate($0.startTime, inSameDayAs: day) }, now: now)
    }

    /// Totals for excursions that started within the shown month or week.
    func shownTotals(now: Date = .now) -> DayTotals {
        let interval = shownInterval
        return totals(of: excursions.filter { interval.contains($0.startTime) }, now: now)
    }

    private func totals(of excursions: [Excursion], now: Date) -> DayTotals {
        let walks = excursions.filter { !$0.isLikelyVehicleTrip }
        return DayTotals(
            walkCount: walks.count,
            distanceMeters: walks.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
            durationSeconds: walks.reduce(0) { $0 + ($1.duration ?? now.timeIntervalSince($1.startTime)) }
        )
    }

    struct DayTotals: Equatable {
        let walkCount: Int
        let distanceMeters: Double
        let durationSeconds: TimeInterval
    }

    /// The longest distance on any day of the shown month, for scaling
    /// the month grid's day colors.
    var maximumDailyDistanceInShownMonth: Double {
        guard let month = calendar.dateInterval(of: .month, for: anchor) else { return 0 }
        return days(in: month).map { totals(on: $0).distanceMeters }.max() ?? 0
    }

    /// The hour the first excursion on `day` starts in (0 for one that
    /// began the day before), `nil` without any.
    func firstExcursionHour(on day: Date) -> Int? {
        guard let first = excursions(on: day).first else { return nil }
        guard calendar.isDate(first.startTime, inSameDayAs: day) else { return 0 }
        return calendar.component(.hour, from: first.startTime)
    }

    /// Where `excursion` sits within `day`, as fractions of the day from 0
    /// to 1, clipped to the day for one that started the day before or
    /// ends the next, and running up to `now` while still ongoing.
    func dayFractions(of excursion: Excursion, on day: Date, now: Date = .now) -> ClosedRange<Double>? {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
        let start = max(excursion.startTime, interval.start)
        let end = min(excursion.endTime ?? now, interval.end)
        guard end > start else { return nil }
        let length = interval.duration
        return start.timeIntervalSince(interval.start) / length...end.timeIntervalSince(interval.start) / length
    }
}
