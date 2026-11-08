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
    /// Gates the "Share `<Pet>`" action, the avatar's edit-photo affordance,
    /// and the Trail/Excursions rows, each straight off what Traccar's own
    /// permission flags allow the signed-in account to do (see ADR-0018,
    /// ADR-0023). `nil` until ``loadPermissions()`` resolves, every gated
    /// affordance stays hidden until then.
    private(set) var permissions: AccountPermissions?

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

    /// Best-effort, same reasoning as ``loadLifetimeStats()``: this just
    /// gates UI affordances, not something worth surfacing an error for.
    func loadPermissions() async {
        permissions = try? await petRepository.currentUserPermissions()
    }

    func setPhoto(jpegData: Data) async throws {
        try await petRepository.setPhoto(forPetID: pet.id, jpegData: jpegData)
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
