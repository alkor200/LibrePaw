#if DEBUG
import Foundation
import LibrePawKit

// Sample data and in-memory fakes used only by SwiftUI previews (see ADR-0009).
// None of this is compiled into release builds.
//
// The walk below is a made-up loop through Tempelhofer Feld in Berlin, used
// for both previews and (temporarily, via AppDependencies.preview()) for
// capturing marketing screenshots with realistic-looking data instead of
// live account details.

extension Pet {
    static let previewOnline = Pet(
        id: 1,
        name: "Buddy",
        species: "dog",
        status: .online,
        lastSeenAt: .now,
        lastPosition: PetPosition.previewTrail.last
    )

    /// Only used by other views' own `#Preview` canvases that want a
    /// second, offline-looking pet, not part of the main screenshot flow.
    static let previewOffline = Pet(
        id: 2,
        name: "Whiskers",
        species: "cat",
        status: .offline,
        lastSeenAt: .now.addingTimeInterval(-3600 * 5),
        lastPosition: nil
    )
}

extension Coordinate {
    static let previewHome = Coordinate(latitude: 52.4720, longitude: 13.3978)
}

extension PetPosition {
    /// A loop through Tempelhofer Feld, oldest first, each point a few
    /// minutes apart, ending at the pet's current (still out) position.
    static let previewTrail: [PetPosition] = {
        let points: [(lat: Double, lon: Double, minutesAgo: Double, speed: Double)] = [
            (52.4720, 13.3978, 42, 3.8),
            (52.4726, 13.3992, 39, 4.6),
            (52.4732, 13.4008, 36, 5.1),
            (52.4739, 13.4022, 33, 4.4),
            (52.4745, 13.4035, 30, 3.9),
            (52.4751, 13.4048, 27, 4.8),
            (52.4756, 13.4061, 24, 2.1),
            (52.4760, 13.4072, 21, 4.3),
            (52.4757, 13.4082, 18, 3.6),
            (52.4750, 13.4088, 15, 0.4),
            (52.4745, 13.4080, 12, 4.1),
            (52.4748, 13.4070, 9, 3.3),
            (52.4752, 13.4068, 6, 2.6),
            (52.4755, 13.4065, 3, 1.8),
            (52.4756, 13.4063, 0, 1.2)
        ]
        return points.enumerated().map { index, point in
            PetPosition(
                id: index + 1,
                petID: 1,
                coordinate: Coordinate(latitude: point.lat, longitude: point.lon),
                recordedAt: .now.addingTimeInterval(-point.minutesAgo * 60),
                speedKilometersPerHour: point.speed,
                address: "Tempelhofer Feld, Berlin",
                batteryLevelPercent: 71
            )
        }
    }()
}

struct PreviewPetRepository: PetRepository {
    func fetchPets() async throws -> [Pet] {
        [.previewOnline]
    }

    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition] {
        PetPosition.previewTrail
    }

    func fetchPhoto(for pet: Pet) async throws -> Data? {
        nil
    }

    func setPhoto(forPetID petID: Int, jpegData: Data) async throws {}

    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([.previewOnline])
            continuation.finish()
        }
    }

    func homeGeofences(forPetID petID: Int) async throws -> [HomeGeofence] {
        [HomeGeofence(id: 1, name: "Home", center: .previewHome, radiusMeters: 70)]
    }

    func addHomeGeofence(forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {}
    func updateHomeGeofence(_ homeID: Int, forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {}
    func deleteHomeGeofence(_ homeID: Int) async throws {}

    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion] {
        [
            Excursion(
                id: 1,
                startTime: .now.addingTimeInterval(-42 * 60),
                endTime: nil,
                startCoordinate: .previewHome,
                endCoordinate: nil,
                distanceMeters: 890,
                startHomeID: 1,
                endHomeID: nil
            ),
            Excursion(
                id: 2,
                startTime: .now.addingTimeInterval(-3600 * 23),
                endTime: .now.addingTimeInterval(-3600 * 22.4),
                startCoordinate: .previewHome,
                endCoordinate: .previewHome,
                distanceMeters: 1050,
                startHomeID: 1,
                endHomeID: 1
            ),
            Excursion(
                id: 3,
                startTime: .now.addingTimeInterval(-3600 * 32),
                endTime: .now.addingTimeInterval(-3600 * 31.6),
                startCoordinate: .previewHome,
                endCoordinate: .previewHome,
                distanceMeters: 680,
                startHomeID: 1,
                endHomeID: 1
            ),
            Excursion(
                id: 4,
                startTime: .now.addingTimeInterval(-3600 * 56),
                endTime: .now.addingTimeInterval(-3600 * 54.97),
                startCoordinate: .previewHome,
                endCoordinate: .previewHome,
                distanceMeters: 2100,
                startHomeID: 1,
                endHomeID: 1
            )
        ]
    }

    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats {
        LifetimeStats(totalDistanceMeters: 46_800, totalDurationSeconds: 3600 * 15.5)
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
