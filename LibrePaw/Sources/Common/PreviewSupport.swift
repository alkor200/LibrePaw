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
    /// The *shape* is a real route through an actual German park, not
    /// invented, and not American either (a Central Park, NYC shape was
    /// tried first, it worked but a US running loop is an odd thing for a
    /// Berlin dog to be walking). Routed live through OpenStreetMap's own
    /// public foot-routing service (`routing.openstreetmap.de`, no API key)
    /// around real paths in Berlin's Tiergarten: Große Sternallee, across
    /// the Hiroshimasteg footbridge, along the Landwehrkanal on
    /// Herkulesufer, back to the start. That real route's own fixes are
    /// resampled to 162 (keeping its real turn-by-turn shape, not
    /// re-smoothed), uniformly scaled down to exactly 3500m, and relocated
    /// to start and end at the house next to Tempelhofer Feld, one fix
    /// every 30 seconds (the real Mictrack report interval, see ADR-0025)
    /// at an average 2.6 km/h.
    static func previewRouteB(endingAt end: Date) -> [PetPosition] {
        let fixes: [(lat: Double, lon: Double, speedKmh: Double)] = [
            (52.472000, 13.397800, 2.6), (52.471994, 13.398125, 2.6), (52.471984, 13.398449, 2.6),
            (52.471979, 13.398774, 2.6), (52.471977, 13.399099, 2.6), (52.471979, 13.399424, 2.6),
            (52.471996, 13.399747, 2.6), (52.472017, 13.400070, 2.6), (52.472054, 13.400389, 2.6),
            (52.472090, 13.400709, 2.6), (52.472127, 13.401028, 2.6), (52.472178, 13.401342, 2.6),
            (52.472230, 13.401655, 2.6), (52.472283, 13.401968, 2.6), (52.472350, 13.402273, 2.6),
            (52.472433, 13.402569, 2.6), (52.472534, 13.402847, 2.6), (52.472646, 13.403113, 2.6),
            (52.472782, 13.403351, 2.6), (52.472917, 13.403588, 2.6), (52.473055, 13.403820, 2.6),
            (52.473204, 13.404033, 2.6), (52.473362, 13.404230, 2.6), (52.473513, 13.404438, 2.6),
            (52.473653, 13.404667, 2.6), (52.473772, 13.404927, 2.6), (52.473883, 13.405196, 2.6),
            (52.473986, 13.405473, 2.6), (52.474069, 13.405768, 2.6), (52.474153, 13.406062, 2.6),
            (52.474229, 13.406362, 2.6), (52.474290, 13.406671, 2.6), (52.474350, 13.406980, 2.6),
            (52.474407, 13.407288, 2.6), (52.474304, 13.407565, 2.6), (52.474191, 13.407832, 2.6),
            (52.474078, 13.408098, 2.6), (52.473966, 13.408366, 2.6), (52.473853, 13.408633, 2.6),
            (52.473740, 13.408900, 2.6), (52.473627, 13.409167, 2.6), (52.473514, 13.409434, 2.6),
            (52.473401, 13.409700, 2.6), (52.473289, 13.409967, 2.6), (52.473176, 13.410234, 2.6),
            (52.473063, 13.410501, 2.6), (52.472950, 13.410768, 2.6), (52.472837, 13.411035, 2.6),
            (52.472724, 13.411301, 2.6), (52.472611, 13.411568, 2.6), (52.472498, 13.411835, 2.6),
            (52.472385, 13.412102, 2.0), (52.472248, 13.412185, 2.6), (52.472075, 13.412029, 2.6),
            (52.471888, 13.411922, 2.6), (52.471700, 13.411821, 2.6), (52.471510, 13.411728, 2.6),
            (52.471322, 13.411628, 2.5), (52.471138, 13.411645, 2.5), (52.470955, 13.411710, 2.6),
            (52.470767, 13.411610, 2.6), (52.470578, 13.411511, 2.6), (52.470390, 13.411411, 2.6),
            (52.470202, 13.411311, 2.6), (52.470013, 13.411211, 2.6), (52.469825, 13.411111, 2.6),
            (52.469636, 13.411012, 2.6), (52.469448, 13.410912, 2.6), (52.469260, 13.410813, 2.6),
            (52.469071, 13.410713, 2.6), (52.468883, 13.410614, 2.6), (52.468695, 13.410513, 2.6),
            (52.468506, 13.410414, 2.6), (52.468318, 13.410314, 2.6), (52.468130, 13.410214, 2.6),
            (52.467941, 13.410115, 2.6), (52.467753, 13.410016, 2.6), (52.467564, 13.409916, 2.6),
            (52.467376, 13.409816, 2.6), (52.467188, 13.409716, 2.6), (52.466999, 13.409616, 2.6),
            (52.466811, 13.409517, 2.6), (52.466623, 13.409417, 2.6), (52.466434, 13.409318, 2.3),
            (52.466265, 13.409283, 2.6), (52.466076, 13.409190, 2.3), (52.465985, 13.409433, 1.5),
            (52.465900, 13.409555, 2.6), (52.465929, 13.409234, 2.6), (52.465949, 13.408911, 2.6),
            (52.465956, 13.408586, 2.6), (52.465959, 13.408261, 2.6), (52.465960, 13.407936, 2.6),
            (52.465962, 13.407612, 2.6), (52.465964, 13.407287, 2.6), (52.465960, 13.406962, 2.6),
            (52.465923, 13.406644, 2.6), (52.465856, 13.406340, 2.6), (52.465751, 13.406068, 2.6),
            (52.465617, 13.405828, 2.5), (52.465443, 13.405713, 2.6), (52.465304, 13.405487, 2.6),
            (52.465220, 13.405193, 2.6), (52.465145, 13.404893, 2.6), (52.465069, 13.404593, 2.6),
            (52.464993, 13.404293, 2.6), (52.464918, 13.403992, 2.6), (52.464843, 13.403692, 2.6),
            (52.464770, 13.403390, 2.6), (52.464697, 13.403088, 2.6), (52.464624, 13.402786, 2.6),
            (52.464550, 13.402484, 2.6), (52.464477, 13.402183, 2.6), (52.464404, 13.401881, 2.6),
            (52.464332, 13.401578, 2.6), (52.464262, 13.401274, 2.6), (52.464210, 13.400963, 2.6),
            (52.464187, 13.400640, 2.6), (52.464174, 13.400316, 2.6), (52.464214, 13.400000, 2.5),
            (52.464391, 13.399907, 2.6), (52.464588, 13.399871, 2.6), (52.464785, 13.399835, 2.5),
            (52.464969, 13.399881, 2.4), (52.465152, 13.399901, 2.0), (52.465297, 13.399984, 2.3),
            (52.465471, 13.400004, 2.6), (52.465667, 13.399965, 2.6), (52.465864, 13.399925, 2.6),
            (52.466060, 13.399885, 2.6), (52.466257, 13.399843, 2.6), (52.466453, 13.399801, 2.6),
            (52.466648, 13.399753, 2.6), (52.466844, 13.399706, 2.6), (52.467040, 13.399659, 2.6),
            (52.467236, 13.399612, 2.6), (52.467432, 13.399564, 2.6), (52.467627, 13.399515, 2.6),
            (52.467823, 13.399466, 2.6), (52.468019, 13.399417, 2.6), (52.468214, 13.399368, 2.6),
            (52.468410, 13.399319, 2.6), (52.468606, 13.399270, 2.6), (52.468801, 13.399218, 2.6),
            (52.468996, 13.399165, 2.6), (52.469191, 13.399113, 2.6), (52.469387, 13.399060, 2.6),
            (52.469582, 13.399009, 2.6), (52.469778, 13.398962, 2.6), (52.469974, 13.398914, 2.6),
            (52.470169, 13.398865, 2.6), (52.470365, 13.398817, 2.6), (52.470555, 13.398739, 2.6),
            (52.470747, 13.398665, 2.6), (52.470940, 13.398593, 2.6), (52.471134, 13.398558, 2.6),
            (52.471330, 13.398506, 2.6), (52.471525, 13.398455, 2.6), (52.471721, 13.398403, 2.6),
            (52.471916, 13.398352, 2.1), (52.471994, 13.398126, 2.6), (52.472000, 13.397800, 2.6)
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
