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

    /// Three more made-up, differently-shaped walks through Tempelhofer
    /// Feld, each home-to-home, matching `PreviewPetRepository`'s other
    /// three (completed) mock excursions, so `TrailView` draws genuinely
    /// distinct routes instead of the same one three times over in
    /// different colors.
    private static func previewRoute(_ points: [(lat: Double, lon: Double)], idOffset: Int, endingAt end: Date, durationSeconds: TimeInterval) -> [PetPosition] {
        let lastIndex = points.count - 1
        return points.enumerated().map { index, point in
            let secondsBeforeEnd = durationSeconds * Double(lastIndex - index) / Double(max(lastIndex, 1))
            return PetPosition(
                id: idOffset + index,
                petID: 1,
                coordinate: Coordinate(latitude: point.lat, longitude: point.lon),
                recordedAt: end.addingTimeInterval(-secondsBeforeEnd),
                speedKilometersPerHour: 3.6,
                address: "Tempelhofer Feld, Berlin",
                batteryLevelPercent: 71
            )
        }
    }

    /// Matches `fetchExcursions`' second mock excursion (23h ago, 1050m).
    static func previewRouteB(endingAt end: Date) -> [PetPosition] {
        previewRoute([
            (52.4720, 13.3978), (52.4713, 13.3995), (52.4705, 13.4015), (52.4698, 13.4035),
            (52.4702, 13.4055), (52.4712, 13.4060), (52.4720, 13.4040), (52.4722, 13.4010),
            (52.4720, 13.3978)
        ], idOffset: 100, endingAt: end, durationSeconds: 36 * 60)
    }

    /// Matches `fetchExcursions`' third mock excursion (32h ago, 680m).
    static func previewRouteC(endingAt end: Date) -> [PetPosition] {
        previewRoute([
            (52.4720, 13.3978), (52.4728, 13.3990), (52.4735, 13.4000),
            (52.4730, 13.4012), (52.4722, 13.4005), (52.4718, 13.3992), (52.4720, 13.3978)
        ], idOffset: 200, endingAt: end, durationSeconds: 24 * 60)
    }

    /// Matches `fetchExcursions`' fourth mock excursion (56h ago, 2100m).
    static func previewRouteD(endingAt end: Date) -> [PetPosition] {
        previewRoute([
            (52.4720, 13.3978), (52.4735, 13.3995), (52.4750, 13.4015), (52.4762, 13.4040),
            (52.4768, 13.4065), (52.4760, 13.4085), (52.4745, 13.4090), (52.4730, 13.4075),
            (52.4720, 13.4050), (52.4715, 13.4020), (52.4718, 13.3995), (52.4720, 13.3978)
        ], idOffset: 300, endingAt: end, durationSeconds: 61.8 * 60)
    }

    /// Matches `fetchExcursions`' fifth mock excursion (10h ago, 1480m), a
    /// denser, more meandering half-hour loop (28 fixes rather than the
    /// handful above) starting and ending a short way inside the field from
    /// its own entrance, same as every other route here, used for the
    /// website's hero screenshot.
    static func previewRouteE(endingAt end: Date) -> [PetPosition] {
        previewRoute([
            (52.4720, 13.3978), (52.4717, 13.3984), (52.4712, 13.3990), (52.4706, 13.3998),
            (52.4700, 13.4006), (52.4694, 13.4014), (52.4688, 13.4022), (52.4683, 13.4030),
            (52.4679, 13.4040), (52.4676, 13.4050), (52.4680, 13.4058), (52.4685, 13.4052),
            (52.4680, 13.4046), (52.4675, 13.4055), (52.4678, 13.4064), (52.4684, 13.4060),
            (52.4690, 13.4052), (52.4696, 13.4044), (52.4702, 13.4050), (52.4698, 13.4058),
            (52.4704, 13.4062), (52.4710, 13.4055), (52.4706, 13.4044), (52.4712, 13.4036),
            (52.4718, 13.4024), (52.4712, 13.4012), (52.4718, 13.4000), (52.4720, 13.3978)
        ], idOffset: 400, endingAt: end, durationSeconds: 30 * 60)
    }
}

struct PreviewPetRepository: PetRepository {
    func fetchPets() async throws -> [Pet] {
        [.previewOnline]
    }

    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition] {
        // Matches `from` against each mock excursion's own start time (see
        // `fetchExcursions` below) so `TrailView`, which fetches one trail
        // per excursion using its own start/end, draws a genuinely
        // different-shaped route per excursion instead of the same one
        // three times over in different colors. Falls back to the
        // original loop for anything else (e.g. `loadTodaysExcursions`'s
        // `startOfDay` window, which matches none of these).
        let referenceNow = Date.now
        let tolerance: TimeInterval = 60
        if abs(from.timeIntervalSince(referenceNow.addingTimeInterval(-3600 * 23))) < tolerance {
            return PetPosition.previewRouteB(endingAt: to)
        } else if abs(from.timeIntervalSince(referenceNow.addingTimeInterval(-3600 * 32))) < tolerance {
            return PetPosition.previewRouteC(endingAt: to)
        } else if abs(from.timeIntervalSince(referenceNow.addingTimeInterval(-3600 * 56))) < tolerance {
            return PetPosition.previewRouteD(endingAt: to)
        } else if abs(from.timeIntervalSince(referenceNow.addingTimeInterval(-3600 * 10))) < tolerance {
            return PetPosition.previewRouteE(endingAt: to)
        }
        return PetPosition.previewTrail
    }

    func fetchPhoto(for pet: Pet) async throws -> Data? {
        nil
    }

    func setPhoto(forPetID petID: Int, jpegData: Data) async throws {}
    func renamePet(forPetID petID: Int, name: String) async throws {}

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
            ),
            Excursion(
                id: 5,
                startTime: .now.addingTimeInterval(-3600 * 10),
                endTime: .now.addingTimeInterval(-3600 * 9.5),
                startCoordinate: .previewHome,
                endCoordinate: .previewHome,
                distanceMeters: 1480,
                startHomeID: 1,
                endHomeID: 1
            )
        ]
    }

    func resetExcursionsCache(forPetID petID: Int) async throws {}

    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats {
        LifetimeStats(totalDistanceMeters: 46_800, totalDurationSeconds: 3600 * 15.5)
    }

    func resetLifetimeStats(forPetID petID: Int) async throws {}

    func currentUserPermissions() async throws -> AccountPermissions {
        AccountPermissions(isAdministrator: true, canManageHomes: true, canManageDevice: true, canViewExcursions: true)
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
