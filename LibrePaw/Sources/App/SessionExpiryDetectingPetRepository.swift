import Foundation
import LibrePawKit

/// Wraps the session's real ``PetRepository`` and reports any
/// `LibrePawError.invalidCredentials` it throws, from any call or the live
/// feed, to `onInvalidCredentials`, so ``AppSession`` can end a session the
/// server no longer accepts (password changed, account disabled) instead
/// of every screen separately showing "The email or password is incorrect."
/// while the stale credentials keep getting reused on every launch.
///
/// Errors are passed through unchanged either way, this only observes them.
struct SessionExpiryDetectingPetRepository: PetRepository {
    let base: PetRepository
    let onInvalidCredentials: @Sendable () -> Void

    private func checked<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch LibrePawError.invalidCredentials {
            onInvalidCredentials()
            throw LibrePawError.invalidCredentials
        }
    }

    func fetchPets() async throws -> [Pet] {
        try await checked { try await base.fetchPets() }
    }

    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition] {
        try await checked { try await base.fetchTrail(forPetID: petID, from: from, to: to) }
    }

    func fetchPhoto(for pet: Pet) async throws -> Data? {
        try await checked { try await base.fetchPhoto(for: pet) }
    }

    func setPhoto(forPetID petID: Int, jpegData: Data) async throws {
        try await checked { try await base.setPhoto(forPetID: petID, jpegData: jpegData) }
    }

    func renamePet(forPetID petID: Int, name: String) async throws {
        try await checked { try await base.renamePet(forPetID: petID, name: name) }
    }

    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error> {
        let upstream = base.livePetUpdates()
        let onInvalidCredentials = onInvalidCredentials
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await pets in upstream {
                        continuation.yield(pets)
                    }
                    continuation.finish()
                } catch {
                    if case LibrePawError.invalidCredentials = error {
                        onInvalidCredentials()
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func homeGeofences(forPetID petID: Int) async throws -> [HomeGeofence] {
        try await checked { try await base.homeGeofences(forPetID: petID) }
    }

    func addHomeGeofence(forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {
        try await checked { try await base.addHomeGeofence(forPetID: petID, name: name, center: center, radiusMeters: radiusMeters) }
    }

    func updateHomeGeofence(_ homeID: Int, forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {
        try await checked {
            try await base.updateHomeGeofence(homeID, forPetID: petID, name: name, center: center, radiusMeters: radiusMeters)
        }
    }

    func deleteHomeGeofence(_ homeID: Int) async throws {
        try await checked { try await base.deleteHomeGeofence(homeID) }
    }

    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion] {
        try await checked { try await base.fetchExcursions(forPetID: petID, from: from, to: to) }
    }

    func resetExcursionsCache(forPetID petID: Int) async throws {
        try await checked { try await base.resetExcursionsCache(forPetID: petID) }
    }

    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats {
        try await checked { try await base.lifetimeExcursionStats(forPetID: petID) }
    }

    func resetLifetimeStats(forPetID petID: Int) async throws {
        try await checked { try await base.resetLifetimeStats(forPetID: petID) }
    }

    func currentUserPermissions() async throws -> AccountPermissions {
        try await checked { try await base.currentUserPermissions() }
    }

    func sharePet(forPetID petID: Int, withEmail email: String) async throws {
        try await checked { try await base.sharePet(forPetID: petID, withEmail: email) }
    }

    func endSession() async {
        await base.endSession()
    }
}
