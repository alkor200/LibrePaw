import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("LivePetFeed")
@MainActor
struct LivePetFeedTests {
    @Test("A feed whose first connection fails is retried instead of given up on")
    func retriesAfterInitialFailure() async {
        let repository = ScriptedFeedRepository(attempts: [.failure(LibrePawError.network("offline")), .success([.feedTestPet])])
        var errors: [Error] = []
        var updates: [[Pet]] = []

        await LivePetFeed.run(repository, retryDelay: .milliseconds(1)) { pets in
            updates.append(pets)
            return false
        } onError: { error in
            errors.append(error)
        }

        #expect(errors.count == 1)
        #expect(updates.map { $0.map(\.id) } == [[Pet.feedTestPet.id]])
    }

    @Test("invalidCredentials is never retried, the session is ending anyway")
    func doesNotRetryInvalidCredentials() async {
        let repository = ScriptedFeedRepository(attempts: [.failure(LibrePawError.invalidCredentials), .success([.feedTestPet])])
        var updates = 0

        await LivePetFeed.run(repository, retryDelay: .milliseconds(1)) { _ in
            updates += 1
            return true
        }

        #expect(updates == 0)
        #expect(repository.attemptCount == 1)
    }
}

private extension Pet {
    static let feedTestPet = Pet(id: 7, name: "Rex", species: nil, status: .online, lastSeenAt: nil, lastPosition: nil)
}

/// Each `livePetUpdates()` call plays the next scripted attempt: either
/// fails right away, or yields one snapshot and finishes.
private final class ScriptedFeedRepository: PetRepository, @unchecked Sendable {
    private var attempts: [Result<[Pet], Error>]
    private(set) var attemptCount = 0

    init(attempts: [Result<[Pet], Error>]) {
        self.attempts = attempts
    }

    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error> {
        attemptCount += 1
        let attempt = attempts.isEmpty ? .success([]) : attempts.removeFirst()
        return AsyncThrowingStream { continuation in
            switch attempt {
            case .success(let pets):
                continuation.yield(pets)
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }

    func fetchPets() async throws -> [Pet] { [] }
    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition] { [] }
    func fetchPhoto(for pet: Pet) async throws -> Data? { nil }
    func setPhoto(forPetID petID: Int, jpegData: Data) async throws {}
    func renamePet(forPetID petID: Int, name: String) async throws {}
    func homeGeofences(forPetID petID: Int) async throws -> [HomeGeofence] { [] }
    func addHomeGeofence(forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {}
    func updateHomeGeofence(_ homeID: Int, forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {}
    func deleteHomeGeofence(_ homeID: Int) async throws {}
    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion] { [] }
    func resetExcursionsCache(forPetID petID: Int) async throws {}
    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats { .zero }
    func resetLifetimeStats(forPetID petID: Int) async throws {}
    func currentUserPermissions() async throws -> AccountPermissions {
        AccountPermissions(isAdministrator: false, canManageHomes: true, canManageDevice: true, canViewExcursions: true)
    }
    func sharePet(forPetID petID: Int, withEmail email: String) async throws {}
    func endSession() async {}
}
