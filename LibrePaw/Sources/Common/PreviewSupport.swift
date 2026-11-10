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

    /// Matches `fetchExcursions`' second mock excursion (23h ago, 3500m).
    /// The *shape* is a real recorded route, not invented: the reservoir +
    /// bridle-trail running loop from viewmygpx.com's CC0 "Central Park
    /// 10 km" sample GPX (a synthetic random walk was tried first and
    /// looked exactly like what it was, an algorithm's idea of a path, not
    /// a real one). That loop's 1100 real fixes are subsampled down to 162
    /// (keeping its own real point-to-point spacing pattern, not
    /// re-smoothed), uniformly scaled from its real ~10 km down to exactly
    /// 3500m, and relocated to start and end at the house next to
    /// Tempelhofer Feld, one fix every 30 seconds (the real Mictrack report
    /// interval, see ADR-0025) at an average 2.6 km/h.
    static func previewRouteB(endingAt end: Date) -> [PetPosition] {
        let fixes: [(lat: Double, lon: Double, speedKmh: Double)] = [
            (52.472000, 13.397800, 2.8), (52.472208, 13.397762, 2.6), (52.472402, 13.397733, 2.4),
            (52.472581, 13.397708, 2.6), (52.472773, 13.397674, 2.7), (52.472973, 13.397652, 2.8),
            (52.473180, 13.397618, 2.7), (52.473381, 13.397587, 2.6), (52.473577, 13.397556, 2.3),
            (52.473745, 13.397526, 2.7), (52.473950, 13.397495, 2.5), (52.474123, 13.397602, 2.7),
            (52.474269, 13.397825, 2.7), (52.474420, 13.398045, 2.7), (52.474568, 13.398273, 2.3),
            (52.474693, 13.398461, 2.7), (52.474839, 13.398682, 2.7), (52.474985, 13.398908, 2.7),
            (52.475130, 13.399131, 2.7), (52.475282, 13.399355, 2.6), (52.475425, 13.399576, 2.4),
            (52.475560, 13.399775, 2.7), (52.475708, 13.399995, 2.7), (52.475855, 13.400226, 2.5),
            (52.475894, 13.400526, 2.6), (52.475915, 13.400850, 2.4), (52.475925, 13.401141, 2.6),
            (52.475937, 13.401464, 2.7), (52.475960, 13.401799, 2.7), (52.475974, 13.402130, 2.7),
            (52.475990, 13.402458, 2.6), (52.476003, 13.402778, 2.4), (52.476020, 13.403067, 2.5),
            (52.476013, 13.403379, 2.7), (52.475877, 13.403623, 2.6), (52.475743, 13.403860, 2.7),
            (52.475604, 13.404105, 2.6), (52.475470, 13.404343, 2.4), (52.475343, 13.404544, 2.7),
            (52.475215, 13.404794, 2.7), (52.475067, 13.405025, 2.6), (52.474937, 13.405264, 2.7),
            (52.474798, 13.405509, 2.6), (52.474603, 13.405544, 2.3), (52.474432, 13.405566, 2.7),
            (52.474231, 13.405591, 2.7), (52.474027, 13.405624, 2.6), (52.473831, 13.405647, 2.7),
            (52.473630, 13.405671, 2.4), (52.473452, 13.405692, 2.6), (52.473256, 13.405714, 2.7),
            (52.473054, 13.405741, 2.8), (52.472849, 13.405768, 2.6), (52.472657, 13.405803, 2.7),
            (52.472457, 13.405828, 2.3), (52.472296, 13.405744, 2.8), (52.472107, 13.405597, 2.6),
            (52.471933, 13.405460, 2.7), (52.471750, 13.405316, 2.7), (52.471567, 13.405168, 2.6),
            (52.471393, 13.405031, 2.4), (52.471231, 13.404896, 2.7), (52.471047, 13.404755, 2.7),
            (52.470867, 13.404618, 2.7), (52.470690, 13.404467, 2.6), (52.470512, 13.404331, 2.7),
            (52.470333, 13.404186, 2.4), (52.470174, 13.404059, 2.6), (52.470020, 13.403870, 2.7),
            (52.469893, 13.403604, 2.6), (52.469776, 13.403346, 2.7), (52.469653, 13.403081, 2.3),
            (52.469548, 13.402861, 2.8), (52.469421, 13.402595, 2.6), (52.469301, 13.402344, 2.8),
            (52.469171, 13.402072, 2.6), (52.469057, 13.401814, 2.7), (52.468935, 13.401549, 2.3),
            (52.468822, 13.401332, 2.6), (52.468705, 13.401069, 2.7), (52.468578, 13.400813, 2.7),
            (52.468460, 13.400550, 2.7), (52.468335, 13.400289, 2.7), (52.468241, 13.399998, 2.4),
            (52.468148, 13.399751, 2.7), (52.468053, 13.399464, 2.7), (52.467961, 13.399170, 2.7),
            (52.467859, 13.398880, 2.6), (52.467762, 13.398597, 2.7), (52.467666, 13.398309, 2.4),
            (52.467583, 13.398053, 2.6), (52.467488, 13.397768, 2.6), (52.467395, 13.397481, 2.7),
            (52.467290, 13.397191, 2.7), (52.467197, 13.396902, 2.3), (52.467116, 13.396651, 2.6),
            (52.467038, 13.396353, 2.6), (52.466983, 13.396040, 2.7), (52.466920, 13.395719, 2.7),
            (52.466855, 13.395406, 2.6), (52.466793, 13.395098, 2.3), (52.466735, 13.394833, 2.8),
            (52.466673, 13.394510, 2.6), (52.466614, 13.394203, 2.7), (52.466550, 13.393887, 2.7),
            (52.466482, 13.393578, 2.7), (52.466420, 13.393260, 2.3), (52.466367, 13.392995, 2.5),
            (52.466386, 13.392689, 2.6), (52.466467, 13.392394, 2.7), (52.466552, 13.392098, 2.7),
            (52.466639, 13.391802, 2.7), (52.466729, 13.391506, 2.3), (52.466805, 13.391252, 2.7),
            (52.466890, 13.390949, 2.7), (52.466980, 13.390655, 2.7), (52.467070, 13.390357, 2.6),
            (52.467151, 13.390060, 2.3), (52.467223, 13.389797, 2.7), (52.467310, 13.389500, 2.5),
            (52.467494, 13.389435, 2.7), (52.467697, 13.389410, 2.7), (52.467895, 13.389381, 2.6),
            (52.468091, 13.389352, 2.3), (52.468265, 13.389335, 2.7), (52.468470, 13.389304, 2.6),
            (52.468668, 13.389282, 2.7), (52.468872, 13.389259, 2.7), (52.469073, 13.389236, 2.7),
            (52.469272, 13.389213, 2.3), (52.469439, 13.389181, 2.7), (52.469643, 13.389158, 2.5),
            (52.469831, 13.389171, 2.7), (52.469906, 13.389478, 2.7), (52.469976, 13.389787, 2.8),
            (52.470062, 13.390094, 2.2), (52.470124, 13.390345, 2.7), (52.470200, 13.390658, 2.6),
            (52.470273, 13.390959, 2.8), (52.470353, 13.391271, 2.7), (52.470433, 13.391572, 2.3),
            (52.470497, 13.391836, 2.6), (52.470570, 13.392129, 2.7), (52.470647, 13.392441, 2.7),
            (52.470732, 13.392748, 2.7), (52.470808, 13.393053, 2.6), (52.470883, 13.393354, 2.3),
            (52.470950, 13.393618, 2.6), (52.471022, 13.393914, 2.8), (52.471098, 13.394228, 2.7),
            (52.471178, 13.394533, 2.7), (52.471260, 13.394832, 2.7), (52.471330, 13.395138, 2.4),
            (52.471404, 13.395405, 2.6), (52.471479, 13.395699, 2.7), (52.471549, 13.396011, 2.7),
            (52.471627, 13.396315, 2.7), (52.471710, 13.396621, 2.7), (52.471784, 13.396927, 2.2),
            (52.471846, 13.397179, 2.7), (52.471932, 13.397486, 2.7), (52.472000, 13.397800, 2.7)
        ]
        let lastIndex = fixes.count - 1
        return fixes.enumerated().map { index, fix in
            PetPosition(
                id: 100 + index,
                petID: 1,
                coordinate: Coordinate(latitude: fix.lat, longitude: fix.lon),
                recordedAt: end.addingTimeInterval(-30.0 * Double(lastIndex - index)),
                speedKilometersPerHour: fix.speedKmh,
                address: "Tempelhofer Feld, Berlin",
                batteryLevelPercent: 71
            )
        }
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
                // Exactly 161 fixes * 30s after start, matching
                // `previewRouteB`'s own 162-fix, 30-second-interval trail.
                endTime: .now.addingTimeInterval(-3600 * 23 + 161 * 30),
                startCoordinate: .previewHome,
                endCoordinate: .previewHome,
                distanceMeters: 3500,
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
