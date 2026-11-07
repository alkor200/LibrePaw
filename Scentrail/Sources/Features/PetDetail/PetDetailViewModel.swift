import Foundation
import ScentrailKit

@Observable
@MainActor
final class PetDetailViewModel {
    let pet: Pet
    private(set) var trail: [PetPosition] = []
    private(set) var isLoadingTrail = false
    private(set) var trailErrorMessage: String?
    private(set) var lifetimeStats: LifetimeStats?

    private let petRepository: PetRepository

    init(pet: Pet, petRepository: PetRepository) {
        self.pet = pet
        self.petRepository = petRepository
    }

    /// Loads today's position history so the detail map can draw a trail.
    func loadTodaysTrail() async {
        isLoadingTrail = true
        trailErrorMessage = nil
        defer { isLoadingTrail = false }

        do {
            let startOfDay = Calendar.current.startOfDay(for: .now)
            trail = try await petRepository.fetchTrail(forPetID: pet.id, from: startOfDay, to: .now)
        } catch {
            trailErrorMessage = error.localizedDescription
        }
    }

    /// Lifetime distance/time-away totals. Best-effort: leaves the previous
    /// value (or `nil`) in place on failure rather than surfacing an error,
    /// since this is a secondary stat alongside today's trail.
    func loadLifetimeStats() async {
        lifetimeStats = try? await petRepository.lifetimeExcursionStats(forPetID: pet.id)
    }

    /// Total distance covered along today's trail, summing consecutive fixes
    /// with the same spherical-geometry math used by the Find Pet screen.
    /// `nil` until there are at least two points to measure between.
    var totalTrailDistanceMeters: Double? {
        guard trail.count > 1 else { return nil }
        return zip(trail, trail.dropFirst())
            .reduce(0) { $0 + $1.0.coordinate.distanceMeters(to: $1.1.coordinate) }
    }
}
