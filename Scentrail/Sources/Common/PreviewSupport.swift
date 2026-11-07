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

    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([.previewOnline, .previewOffline])
            continuation.finish()
        }
    }

    func homeGeofence(forPetID petID: Int) async throws -> HomeGeofence? {
        HomeGeofence(center: Coordinate(latitude: 52.5200, longitude: 13.4050), radiusMeters: 100)
    }

    func setHomeGeofence(forPetID petID: Int, center: Coordinate, radiusMeters: Double) async throws {}

    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion] {
        [
            Excursion(
                id: 1,
                startTime: .now.addingTimeInterval(-3600 * 3),
                endTime: .now.addingTimeInterval(-3600 * 2),
                startCoordinate: Coordinate(latitude: 52.5200, longitude: 13.4050),
                endCoordinate: Coordinate(latitude: 52.5200, longitude: 13.4050),
                distanceMeters: 1240
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
