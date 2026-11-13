import Foundation
import LibrePawKit

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
    func setPhoto(forPetID petID: Int, jpegData: Data) async throws {}
    func renamePet(forPetID petID: Int, name: String) async throws {}

    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

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
