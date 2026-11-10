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

    /// Matches `fetchExcursions`' second mock excursion (23h ago, 3500m). A
    /// realistic walk rather than a handful of straight-line corners: 162
    /// fixes, one every 30 seconds (the real Mictrack report interval, see
    /// ADR-0025), a meandering loop through Tempelhofer Feld averaging
    /// 2.6 km/h with the speed varying fix to fix the way a real dog walk
    /// does (brief sniffing stops, brisker stretches), not a flat rate.
    /// Generated, not hand-placed: a smooth correlated random walk (each
    /// fix's heading nudged from the last, not placed independently),
    /// softly contained to one patch of the field, then corrected so the
    /// walk closes exactly back on the house it started from and its total
    /// length lands on exactly 3500m.
    static func previewRouteB(endingAt end: Date) -> [PetPosition] {
        let fixes: [(lat: Double, lon: Double, speedKmh: Double)] = [
            (52.472000, 13.397800, 1.5), (52.472021, 13.397976, 1.3), (52.472072, 13.398114, 1.7),
            (52.472165, 13.398250, 1.4), (52.472244, 13.398355, 1.5), (52.472294, 13.398521, 1.4),
            (52.472320, 13.398690, 1.9), (52.472364, 13.398908, 1.5), (52.472449, 13.399036, 1.6),
            (52.472491, 13.399221, 1.5), (52.472482, 13.399408, 1.5), (52.472445, 13.399578, 1.4),
            (52.472421, 13.399748, 1.6), (52.472347, 13.399901, 2.0), (52.472255, 13.400091, 2.6),
            (52.472111, 13.400303, 2.5), (52.471999, 13.400545, 1.9), (52.471952, 13.400772, 2.3),
            (52.471893, 13.401041, 2.2), (52.471861, 13.401301, 2.5), (52.471820, 13.401605, 2.1),
            (52.471785, 13.401857, 2.0), (52.471801, 13.402099, 2.0), (52.471904, 13.402270, 2.3),
            (52.472076, 13.402283, 2.3), (52.472241, 13.402199, 2.4), (52.472400, 13.402067, 3.4),
            (52.472389, 13.401647, 3.9), (52.472222, 13.401259, 3.8), (52.471965, 13.401054, 3.2),
            (52.471728, 13.401111, 2.7), (52.471614, 13.401389, 2.1), (52.471682, 13.401623, 2.5),
            (52.471856, 13.401735, 3.0), (52.472074, 13.401681, 3.4), (52.472303, 13.401507, 4.4),
            (52.472180, 13.400999, 3.7), (52.471911, 13.400871, 3.5), (52.471656, 13.400943, 2.6),
            (52.471524, 13.401172, 1.6), (52.471583, 13.401345, 2.2), (52.471746, 13.401376, 3.0),
            (52.471895, 13.401100, 4.1), (52.471645, 13.400815, 3.6), (52.471378, 13.400878, 2.9),
            (52.471307, 13.401209, 2.8), (52.471487, 13.401383, 3.4), (52.471681, 13.401116, 3.9),
            (52.471429, 13.400867, 2.3), (52.471308, 13.401071, 2.1), (52.471423, 13.401240, 2.5),
            (52.471587, 13.401098, 3.4), (52.471363, 13.400894, 1.6), (52.471323, 13.401086, 1.3),
            (52.471409, 13.401149, 2.3), (52.471562, 13.401017, 3.1), (52.471347, 13.400889, 1.4),
            (52.471310, 13.401056, 1.5), (52.471424, 13.401047, 2.3), (52.471538, 13.400829, 3.3),
            (52.471335, 13.400599, 2.4), (52.471213, 13.400813, 2.0), (52.471317, 13.400992, 2.5),
            (52.471490, 13.400876, 3.3), (52.471261, 13.400712, 2.2), (52.471228, 13.400973, 1.8),
            (52.471357, 13.401044, 2.1), (52.471497, 13.400915, 3.4), (52.471269, 13.400721, 1.8),
            (52.471239, 13.400937, 1.7), (52.471368, 13.400955, 2.4), (52.471508, 13.400760, 3.6),
            (52.471279, 13.400517, 1.9), (52.471230, 13.400731, 2.1), (52.471374, 13.400835, 3.0),
            (52.471535, 13.400576, 3.9), (52.471258, 13.400438, 2.4), (52.471267, 13.400733, 2.9),
            (52.471480, 13.400645, 3.9), (52.471641, 13.400244, 4.5), (52.471313, 13.400137, 2.4),
            (52.471314, 13.400433, 2.2), (52.471474, 13.400487, 2.7), (52.471616, 13.400245, 3.6),
            (52.471389, 13.400008, 2.4), (52.471325, 13.400279, 2.4), (52.471503, 13.400320, 2.8),
            (52.471677, 13.400133, 3.9), (52.471399, 13.399977, 2.5), (52.471356, 13.400275, 2.2),
            (52.471506, 13.400395, 3.1), (52.471676, 13.400137, 3.5), (52.471426, 13.399988, 2.4),
            (52.471286, 13.400168, 2.0), (52.471345, 13.400398, 2.2), (52.471504, 13.400315, 3.1),
            (52.471643, 13.400016, 3.1), (52.471415, 13.399954, 1.6), (52.471424, 13.400153, 1.8),
            (52.471558, 13.400171, 2.4), (52.471712, 13.400014, 3.1), (52.471487, 13.399900, 2.0),
            (52.471453, 13.400135, 2.4), (52.471627, 13.400175, 2.8), (52.471778, 13.399935, 3.7),
            (52.471513, 13.399818, 2.3), (52.471532, 13.400095, 2.9), (52.471735, 13.399965, 3.9),
            (52.471477, 13.399749, 1.9), (52.471481, 13.399989, 2.2), (52.471632, 13.399886, 3.0),
            (52.471762, 13.399588, 3.1), (52.471537, 13.399481, 1.8), (52.471543, 13.399696, 2.5),
            (52.471727, 13.399644, 3.2), (52.471862, 13.399315, 3.0), (52.471638, 13.399335, 1.5),
            (52.471653, 13.399522, 2.1), (52.471809, 13.399481, 3.1), (52.471941, 13.399165, 3.6),
            (52.471670, 13.399116, 2.3), (52.471686, 13.399394, 2.4), (52.471859, 13.399465, 3.7),
            (52.472024, 13.399096, 4.1), (52.471716, 13.399053, 2.6), (52.471804, 13.399333, 2.9),
            (52.472001, 13.399170, 4.0), (52.471728, 13.398971, 2.3), (52.471717, 13.399255, 2.6),
            (52.471907, 13.399299, 3.3), (52.472071, 13.398993, 3.8), (52.471793, 13.398904, 1.8),
            (52.471829, 13.399117, 2.2), (52.471992, 13.399123, 2.7), (52.472128, 13.398881, 3.4),
            (52.471887, 13.398741, 1.6), (52.471897, 13.398937, 2.1), (52.472055, 13.398895, 3.0),
            (52.472145, 13.398556, 2.9), (52.471930, 13.398580, 1.6), (52.471981, 13.398755, 2.7),
            (52.472151, 13.398566, 3.7), (52.471880, 13.398485, 2.0), (52.471900, 13.398729, 2.5),
            (52.472083, 13.398681, 3.5), (52.472255, 13.398354, 4.1), (52.471951, 13.398262, 2.1),
            (52.472011, 13.398498, 2.4), (52.472192, 13.398481, 3.4), (52.472322, 13.398114, 3.6),
            (52.472056, 13.398166, 2.0), (52.472112, 13.398397, 2.7), (52.472274, 13.398208, 3.9),
            (52.472005, 13.398032, 2.0), (52.471976, 13.398273, 2.1), (52.472130, 13.398241, 2.8),
            (52.472235, 13.397941, 3.3), (52.471992, 13.397893, 2.0), (52.471976, 13.398140, 2.0),
            (52.472129, 13.398123, 2.8), (52.472263, 13.397862, 3.5), (52.472000, 13.397800, 3.5)
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
