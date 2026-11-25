import Foundation
import LibrePawKit

/// How far back `TrailView` looks for excursions to show, user-adjustable,
/// default every excursion ever (`allTime`), or any range of whole days
/// the user picks (`custom`, see ``TrailViewModel/customRange``). The
/// default used to be 24 hours (ADR-0020), from before routes were cached,
/// when a long window still took a while to load.
enum TrailWindow: Hashable, Identifiable {
    case allTime, oneDay, threeDays, sevenDays, thirtyDays
    case custom

    /// The ones offered as segments, `custom` has its own button.
    static let presets: [TrailWindow] = [.allTime, .oneDay, .threeDays, .sevenDays, .thirtyDays]

    var id: Self { self }

    var label: String {
        switch self {
        case .allTime: localized("All Time")
        case .oneDay: localized("24 Hours")
        case .threeDays: localized("3 Days")
        case .sevenDays: localized("7 Days")
        case .thirtyDays: localized("30 Days")
        case .custom: localized("Custom Range")
        }
    }

    /// Shorter than ``label`` where it has to be, for the segmented picker:
    /// with five segments plus the custom range button, "24 Stunden" got
    /// truncated in German.
    var segmentLabel: String {
        switch self {
        case .allTime: localized("All")
        case .oneDay: localized("24 h")
        default: label
        }
    }

    /// How far back from now a preset reaches, `nil` for `custom` and
    /// `allTime`, which ``TrailViewModel/interval(now:calendar:)`` handles
    /// itself.
    var timeInterval: TimeInterval? {
        switch self {
        case .allTime: nil
        case .oneDay: 86_400
        case .threeDays: 3 * 86_400
        case .sevenDays: 7 * 86_400
        case .thirtyDays: 30 * 86_400
        case .custom: nil
        }
    }
}

/// Replaces the old single-day "Today's Trail" with an aggregation of
/// excursions over an adjustable window (see ADR-0020): each excursion in
/// range gets its own colored route on the map, distinguishing one walk
/// from the next the same way `ExcursionsView`'s list does, but drawn in
/// place rather than as rows.
@Observable
@MainActor
final class TrailViewModel {
    let pet: Pet
    var window: TrailWindow = .allTime
    /// The days shown while `window` is `.custom`, first through last, both
    /// included. Defaults to the last seven days until the user picks one.
    var customRange: ClosedRange<Date> = (Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now)...Date.now

    /// Everything a load depends on, for `TrailView`'s `.task(id:)`: a new
    /// custom range has to reload just like switching presets does.
    struct LoadKey: Hashable {
        let window: TrailWindow
        let customRange: ClosedRange<Date>?
    }

    var loadKey: LoadKey {
        LoadKey(window: window, customRange: window == .custom ? customRange : nil)
    }

    /// The span `window` currently covers: a preset reaches back from
    /// `now`, a custom range runs from the start of its first day to the
    /// end of its last, but never past `now`.
    func interval(now: Date = .now, calendar: Calendar = .current) -> (from: Date, to: Date) {
        if window == .allTime {
            return (.distantPast, now)
        }
        if let timeInterval = window.timeInterval {
            return (now.addingTimeInterval(-timeInterval), now)
        }
        let from = calendar.startOfDay(for: customRange.lowerBound)
        let endOfLastDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customRange.upperBound)) ?? now
        return (from, min(endOfLastDay, now))
    }

    private(set) var excursions: [Excursion] = []
    private(set) var trailsByExcursionID: [Int: [PetPosition]] = [:]
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    private let petRepository: PetRepository
    /// The most recently started load, so a newer one (e.g. switching
    /// `window`) can cancel a stale one still in flight instead of letting
    /// both race to set the published state, same reasoning as
    /// `HomesViewModel.load()`.
    private var loadTask: Task<Void, Never>?

    init(pet: Pet, petRepository: PetRepository) {
        self.pet = pet
        self.petRepository = petRepository
    }

    func load() async {
        loadTask?.cancel()
        let task = Task { await performLoad() }
        loadTask = task
        // `task` is unstructured, so cancelling the caller (e.g. the view's
        // own `.task` when it pops) wouldn't reach it on its own, every
        // route fetch would keep running for a screen nobody sees.
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performLoad() async {
        isLoading = true
        errorMessage = nil
        // A superseded load must leave `isLoading` alone, the newer load
        // that cancelled it has already set it and is still running.
        defer { if !Task.isCancelled { isLoading = false } }

        do {
            let (from, to) = interval()
            let fetchedExcursions = try await petRepository.fetchExcursions(forPetID: pet.id, from: from, to: to)
            guard !Task.isCancelled else { return }

            let fetchedTrails = try await Self.loadTrails(for: fetchedExcursions, petID: pet.id, petRepository: petRepository)
            guard !Task.isCancelled else { return }

            excursions = fetchedExcursions
            trailsByExcursionID = fetchedTrails
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.userFacingMessage
        }
    }

    /// At most this many route fetches run at once. A 30-day window can
    /// hold a hundred-plus excursions, all at once is too much for a
    /// small self-hosted server, same reasoning (and limit) as
    /// `TraccarPetRepository.fetchExcursions`' own fan-out.
    static let maxConcurrentTrailFetches = 20

    /// One position-history fetch per excursion, bounded to that
    /// excursion's own start/end (or now, if still ongoing) so the drawn
    /// route matches exactly what `ExcursionDetailView` would show for the
    /// same excursion.
    ///
    /// A route that fails to load is just left out (its excursion is still
    /// listed, it simply draws no line) rather than failing the whole
    /// screen. Only when every single one failed is that worth an error.
    static func loadTrails(
        for excursions: [Excursion],
        petID: Int,
        petRepository: PetRepository
    ) async throws -> [Int: [PetPosition]] {
        let results = try await concurrentMap(excursions, maxConcurrent: maxConcurrentTrailFetches) { excursion in
            do {
                let positions = try await petRepository.fetchTrail(forPetID: petID, from: excursion.startTime, to: excursion.endTime ?? .now)
                return (excursion.id, Result<[PetPosition], Error>.success(positions))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return (excursion.id, Result<[PetPosition], Error>.failure(error))
            }
        }

        var trails: [Int: [PetPosition]] = [:]
        var firstError: Error?
        for (excursionID, result) in results {
            switch result {
            case .success(let positions): trails[excursionID] = positions
            case .failure(let error): firstError = firstError ?? error
            }
        }
        if trails.isEmpty, let firstError {
            throw firstError
        }
        return trails
    }
}
