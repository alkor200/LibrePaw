import Foundation
import ScentrailKit

/// Test double for ``AuthenticationService`` with a configurable login outcome.
final class FakeAuthenticationService: AuthenticationService, @unchecked Sendable {
    enum LoginResult {
        case success
        case failure(Error)
    }

    var loginResult: LoginResult

    init(loginResult: LoginResult = .success) {
        self.loginResult = loginResult
    }

    func restoreSession() throws -> StoredSession? { nil }

    func logIn(serverURL: URL, email: String, password: String) async throws -> StoredSession {
        switch loginResult {
        case .success:
            StoredSession(serverURL: serverURL, email: email, password: password)
        case .failure(let error):
            throw error
        }
    }

    func logOut() throws {}

    func makePetRepository(for session: StoredSession) -> PetRepository {
        FakePetRepository()
    }
}

struct FakePetRepository: PetRepository {
    func fetchPets() async throws -> [Pet] { [] }
    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition] { [] }
    func fetchPhoto(for pet: Pet) async throws -> Data? { nil }

    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func homeGeofence(forPetID petID: Int) async throws -> HomeGeofence? { nil }
    func setHomeGeofence(forPetID petID: Int, center: Coordinate, radiusMeters: Double) async throws {}
    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion] { [] }
    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats { .zero }
}
