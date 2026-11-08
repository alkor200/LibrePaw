#if DEBUG
import Foundation
import ScentrailKit

// Sample data and in-memory fakes used only by SwiftUI previews (see ADR-0009).
// None of this is compiled into release builds.

extension Pet {
    static let previewOnline = Pet(
        id: 1,
        name: "Buddy",
        species: "dog",
        status: .online,
        lastSeenAt: .now,
        lastPosition: .previewNearBerlin
    )

    static let previewOffline = Pet(
        id: 2,
        name: "Whiskers",
        species: "cat",
        status: .offline,
        lastSeenAt: .now.addingTimeInterval(-3600 * 5),
        lastPosition: nil
    )
}

extension PetPosition {
    static let previewNearBerlin = PetPosition(
        id: 1,
        petID: 1,
        coordinate: Coordinate(latitude: 52.5200, longitude: 13.4050),
        recordedAt: .now,
        speedKilometersPerHour: 4,
        address: "Alexanderplatz, Berlin",
        batteryLevelPercent: 82
    )
}

struct PreviewPetRepository: PetRepository {
    func fetchPets() async throws -> [Pet] {
        [.previewOnline, .previewOffline]
    }

    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition] {
        [.previewNearBerlin]
    }

    func fetchPhoto(for pet: Pet) async throws -> Data? {
        nil
    }

    func setPhoto(forPetID petID: Int, jpegData: Data) async throws {}

    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([.previewOnline, .previewOffline])
            continuation.finish()
        }
    }

    func homeGeofences(forPetID petID: Int) async throws -> [HomeGeofence] {
        [
            HomeGeofence(id: 1, name: "Home", center: Coordinate(latitude: 52.5200, longitude: 13.4050), radiusMeters: 100),
            HomeGeofence(id: 2, name: "Cabin", center: Coordinate(latitude: 52.4100, longitude: 13.0500), radiusMeters: 60)
        ]
    }

    func addHomeGeofence(forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {}
    func updateHomeGeofence(_ homeID: Int, forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {}
    func deleteHomeGeofence(_ homeID: Int) async throws {}

    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion] {
        [
            Excursion(
                id: 1,
                startTime: .now.addingTimeInterval(-3600 * 3),
                endTime: .now.addingTimeInterval(-3600 * 2),
                startCoordinate: Coordinate(latitude: 52.5200, longitude: 13.4050),
                endCoordinate: Coordinate(latitude: 52.4100, longitude: 13.0500),
                distanceMeters: 1240,
                startHomeID: 1,
                endHomeID: 2
            ),
            Excursion(
                id: 2,
                startTime: .now.addingTimeInterval(-1800),
                endTime: nil,
                startCoordinate: Coordinate(latitude: 52.5200, longitude: 13.4050),
                endCoordinate: nil,
                distanceMeters: 420
            )
        ]
    }

    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats {
        LifetimeStats(totalDistanceMeters: 42_300, totalDurationSeconds: 3600 * 11)
    }

    func currentUserPermissions() async throws -> AccountPermissions {
        AccountPermissions(isAdministrator: true, canManageHomes: true, canManageDevicePhoto: true, canViewExcursions: true)
    }
    func sharePet(forPetID petID: Int, withEmail email: String) async throws {}
}

struct PreviewAuthenticationService: AuthenticationService {
    func restoreSession() throws -> StoredSession? {
        StoredSession(serverURL: URL(string: "https://traccar.example.com")!, email: "owner@example.com", password: "preview")
    }

    func logIn(serverURL: URL, email: String, password: String) async throws -> StoredSession {
        StoredSession(serverURL: serverURL, email: email, password: password)
    }

    func logOut() throws {}

    func makePetRepository(for session: StoredSession) -> PetRepository {
        PreviewPetRepository()
    }
}
#endif
