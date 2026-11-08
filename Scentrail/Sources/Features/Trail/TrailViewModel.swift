import Foundation
import ScentrailKit

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
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

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
            errorMessage = error.localizedDescription
        }
    }

    /// One position-history fetch per excursion, all concurrently, each
    /// bounded to that excursion's own start/end (or now, if still
    /// ongoing) so the drawn route matches exactly what `ExcursionDetailView`
    /// would show for the same excursion.
    private static func loadTrails(
        for excursions: [Excursion],
        petID: Int,
        petRepository: PetRepository
    ) async throws -> [Int: [PetPosition]] {
        try await withThrowingTaskGroup(of: (Int, [PetPosition]).self) { group in
            for excursion in excursions {
                group.addTask {
                    let positions = try await petRepository.fetchTrail(forPetID: petID, from: excursion.startTime, to: excursion.endTime ?? .now)
                    return (excursion.id, positions)
                }
            }

            var result: [Int: [PetPosition]] = [:]
            for try await (excursionID, positions) in group {
                result[excursionID] = positions
            }
            return result
        }
    }
}
