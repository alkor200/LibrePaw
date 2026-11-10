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
    /// to start and end near the house next to Tempelhofer Feld, one fix
    /// every 30 seconds (the real Mictrack report interval, see ADR-0025)
    /// at an average 2.6 km/h. Shifted another 200m (bearing 20°, just east
    /// of due north) from there: without that, the route cut straight
    /// across the A100. A few earlier, smaller shift attempts (NW, then NE
    /// by increasing amounts) all still crossed it, because this stretch
    /// runs right past a real highway interchange, not just one straight
    /// road, where several real roads converge from different angles, so a
    /// shift in most directions clears one of them while cutting across
    /// another. This bearing/distance pair is not a guess: checked live,
    /// per fix, against the real road network via OpenStreetMap's own
    /// routing service's `nearest` endpoint (the same
    /// `routing.openstreetmap.de` used to build the route itself), the 23
    /// fixes that were within 40m of a real road beforehand all clear by
    /// 54m or more after this shift.
    static func previewRouteB(endingAt end: Date) -> [PetPosition] {
        let fixes: [(lat: Double, lon: Double, speedKmh: Double)] = [
            (52.473690, 13.398810, 2.6), (52.473684, 13.399135, 2.6), (52.473674, 13.399459, 2.6),
            (52.473669, 13.399784, 2.6), (52.473667, 13.400109, 2.6), (52.473669, 13.400434, 2.6),
            (52.473686, 13.400757, 2.6), (52.473707, 13.401080, 2.6), (52.473744, 13.401399, 2.6),
            (52.473780, 13.401719, 2.6), (52.473817, 13.402038, 2.6), (52.473868, 13.402352, 2.6),
            (52.473920, 13.402665, 2.6), (52.473973, 13.402978, 2.6), (52.474040, 13.403283, 2.6),
            (52.474123, 13.403579, 2.6), (52.474224, 13.403857, 2.6), (52.474336, 13.404123, 2.6),
            (52.474472, 13.404361, 2.6), (52.474607, 13.404598, 2.6), (52.474745, 13.404830, 2.6),
            (52.474894, 13.405043, 2.6), (52.475052, 13.405240, 2.6), (52.475203, 13.405448, 2.6),
            (52.475343, 13.405677, 2.6), (52.475462, 13.405937, 2.6), (52.475573, 13.406206, 2.6),
            (52.475676, 13.406483, 2.6), (52.475759, 13.406778, 2.6), (52.475843, 13.407072, 2.6),
            (52.475919, 13.407372, 2.6), (52.475980, 13.407681, 2.6), (52.476040, 13.407990, 2.6),
            (52.476097, 13.408298, 2.6), (52.475994, 13.408575, 2.6), (52.475881, 13.408842, 2.6),
            (52.475768, 13.409108, 2.6), (52.475656, 13.409376, 2.6), (52.475543, 13.409643, 2.6),
            (52.475430, 13.409910, 2.6), (52.475317, 13.410177, 2.6), (52.475204, 13.410444, 2.6),
            (52.475091, 13.410710, 2.6), (52.474979, 13.410977, 2.6), (52.474866, 13.411244, 2.6),
            (52.474753, 13.411511, 2.6), (52.474640, 13.411778, 2.6), (52.474527, 13.412045, 2.6),
            (52.474414, 13.412311, 2.6), (52.474301, 13.412578, 2.6), (52.474188, 13.412845, 2.6),
            (52.474075, 13.413112, 2.0), (52.473938, 13.413195, 2.6), (52.473765, 13.413039, 2.6),
            (52.473578, 13.412932, 2.6), (52.473390, 13.412831, 2.6), (52.473200, 13.412738, 2.6),
            (52.473012, 13.412638, 2.5), (52.472828, 13.412655, 2.5), (52.472645, 13.412720, 2.6),
            (52.472457, 13.412620, 2.6), (52.472268, 13.412521, 2.6), (52.472080, 13.412421, 2.6),
            (52.471892, 13.412321, 2.6), (52.471703, 13.412221, 2.6), (52.471515, 13.412121, 2.6),
            (52.471326, 13.412022, 2.6), (52.471138, 13.411922, 2.6), (52.470950, 13.411823, 2.6),
            (52.470761, 13.411723, 2.6), (52.470573, 13.411624, 2.6), (52.470385, 13.411523, 2.6),
            (52.470196, 13.411424, 2.6), (52.470008, 13.411324, 2.6), (52.469820, 13.411224, 2.6),
            (52.469631, 13.411125, 2.6), (52.469443, 13.411026, 2.6), (52.469254, 13.410926, 2.6),
            (52.469066, 13.410826, 2.6), (52.468878, 13.410726, 2.6), (52.468689, 13.410626, 2.6),
            (52.468501, 13.410527, 2.6), (52.468313, 13.410427, 2.6), (52.468124, 13.410328, 2.3),
            (52.467955, 13.410293, 2.6), (52.467766, 13.410200, 2.3), (52.467675, 13.410443, 1.5),
            (52.467590, 13.410565, 2.6), (52.467619, 13.410244, 2.6), (52.467639, 13.409921, 2.6),
            (52.467646, 13.409596, 2.6), (52.467649, 13.409271, 2.6), (52.467650, 13.408946, 2.6),
            (52.467652, 13.408622, 2.6), (52.467654, 13.408297, 2.6), (52.467650, 13.407972, 2.6),
            (52.467613, 13.407654, 2.6), (52.467546, 13.407350, 2.6), (52.467441, 13.407078, 2.6),
            (52.467307, 13.406838, 2.5), (52.467133, 13.406723, 2.6), (52.466994, 13.406497, 2.6),
            (52.466910, 13.406203, 2.6), (52.466835, 13.405903, 2.6), (52.466759, 13.405603, 2.6),
            (52.466683, 13.405303, 2.6), (52.466608, 13.405002, 2.6), (52.466533, 13.404702, 2.6),
            (52.466460, 13.404400, 2.6), (52.466387, 13.404098, 2.6), (52.466314, 13.403796, 2.6),
            (52.466240, 13.403494, 2.6), (52.466167, 13.403193, 2.6), (52.466094, 13.402891, 2.6),
            (52.466022, 13.402588, 2.6), (52.465952, 13.402284, 2.6), (52.465900, 13.401973, 2.6),
            (52.465877, 13.401650, 2.6), (52.465864, 13.401326, 2.6), (52.465904, 13.401010, 2.5),
            (52.466081, 13.400917, 2.6), (52.466278, 13.400881, 2.6), (52.466475, 13.400845, 2.5),
            (52.466659, 13.400891, 2.4), (52.466842, 13.400911, 2.0), (52.466987, 13.400994, 2.3),
            (52.467161, 13.401014, 2.6), (52.467357, 13.400975, 2.6), (52.467554, 13.400935, 2.6),
            (52.467750, 13.400895, 2.6), (52.467947, 13.400853, 2.6), (52.468143, 13.400811, 2.6),
            (52.468338, 13.400763, 2.6), (52.468534, 13.400716, 2.6), (52.468730, 13.400669, 2.6),
            (52.468926, 13.400622, 2.6), (52.469122, 13.400574, 2.6), (52.469317, 13.400525, 2.6),
            (52.469513, 13.400476, 2.6), (52.469709, 13.400427, 2.6), (52.469904, 13.400378, 2.6),
            (52.470100, 13.400329, 2.6), (52.470296, 13.400280, 2.6), (52.470491, 13.400228, 2.6),
            (52.470686, 13.400175, 2.6), (52.470881, 13.400123, 2.6), (52.471077, 13.400070, 2.6),
            (52.471272, 13.400019, 2.6), (52.471468, 13.399972, 2.6), (52.471664, 13.399924, 2.6),
            (52.471859, 13.399875, 2.6), (52.472055, 13.399827, 2.6), (52.472245, 13.399749, 2.6),
            (52.472437, 13.399675, 2.6), (52.472630, 13.399603, 2.6), (52.472824, 13.399568, 2.6),
            (52.473020, 13.399516, 2.6), (52.473215, 13.399465, 2.6), (52.473411, 13.399413, 2.6),
            (52.473606, 13.399362, 2.1), (52.473684, 13.399136, 2.6), (52.473690, 13.398810, 2.6),
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
