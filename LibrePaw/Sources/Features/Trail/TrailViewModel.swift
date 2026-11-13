import Foundation
import LibrePawKit

/// How far back `TrailView` looks for excursions to show, user-adjustable,
/// default 24 hours (see ADR-0020).
enum TrailWindow: CaseIterable, Identifiable {
    case oneDay, threeDays, sevenDays, thirtyDays

    var id: Self { self }

    var label: String {
        switch self {
        case .oneDay: localized("24 Hours")
        case .threeDays: localized("3 Days")
        case .sevenDays: localized("7 Days")
        case .thirtyDays: localized("30 Days")
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .oneDay: 86_400
        case .threeDays: 3 * 86_400
        case .sevenDays: 7 * 86_400
        case .thirtyDays: 30 * 86_400
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
    var window: TrailWindow = .oneDay

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
            let now = Date.now
            let from = now.addingTimeInterval(-window.timeInterval)
            let fetchedExcursions = try await petRepository.fetchExcursions(forPetID: pet.id, from: from, to: now)
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
