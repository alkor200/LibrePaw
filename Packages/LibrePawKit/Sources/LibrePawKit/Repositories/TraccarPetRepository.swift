import Foundation
import TraccarKit

/// `PetRepository` backed by a live Traccar server.
struct TraccarPetRepository: PetRepository {
    let client: TraccarClient
    var lifetimeStatsStore: LifetimeStatsStore = UserDefaultsLifetimeStatsStore()

    func fetchPets() async throws -> [Pet] {
        do {
            async let devices = client.fetchDevices()
            async let positions = client.fetchLatestPositions()

            let latestPositionsByDeviceID = Dictionary(
                uniqueKeysWithValues: try await positions.map { ($0.deviceId, $0) }
            )

            let serverURL = client.serverURL
            return try await devices.map { device in
                PetMapping.pet(from: device, latestPosition: latestPositionsByDeviceID[device.id], serverURL: serverURL)
            }
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition] {
        do {
            let positions = try await client.fetchPositionHistory(deviceId: petID, from: from, to: to)
            return positions
                .sorted { $0.fixTime < $1.fixTime }
                .map(PetMapping.position(from:))
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    func fetchPhoto(for pet: Pet) async throws -> Data? {
        guard let photoURL = pet.photoURL else { return nil }
        do {
            return try await client.fetchData(from: photoURL)
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    func setPhoto(forPetID petID: Int, jpegData: Data) async throws {
        do {
            try await client.updateDeviceImage(deviceId: petID, imageData: jpegData, contentType: "image/jpeg")
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    func livePetUpdates() -> AsyncThrowingStream<[Pet], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let serverURL = client.serverURL
                    var devicesByID: [Int: TraccarDevice] = [:]
                    var positionsByDeviceID: [Int: TraccarPosition] = [:]

                    async let initialDevices = client.fetchDevices()
                    async let initialPositions = client.fetchLatestPositions()
                    devicesByID = Dictionary(uniqueKeysWithValues: try await initialDevices.map { ($0.id, $0) })
                    positionsByDeviceID = Dictionary(uniqueKeysWithValues: try await initialPositions.map { ($0.deviceId, $0) })

                    continuation.yield(Self.pets(devicesByID: devicesByID, positionsByDeviceID: positionsByDeviceID, serverURL: serverURL))

                    for try await update in client.liveUpdates() {
                        guard !Task.isCancelled else { break }

                        var changed = false
                        if let devices = update.devices {
                            for device in devices { devicesByID[device.id] = device }
                            changed = true
                        }
                        if let positions = update.positions {
                            for position in positions { positionsByDeviceID[position.deviceId] = position }
                            changed = true
                        }

                        if changed {
                            continuation.yield(Self.pets(devicesByID: devicesByID, positionsByDeviceID: positionsByDeviceID, serverURL: serverURL))
                        }
                    }
                    continuation.finish()
                } catch let error as TraccarError {
                    continuation.finish(throwing: error.asLibrePawError)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func pets(
        devicesByID: [Int: TraccarDevice],
        positionsByDeviceID: [Int: TraccarPosition],
        serverURL: URL
    ) -> [Pet] {
        devicesByID.values.map { device in
            PetMapping.pet(from: device, latestPosition: positionsByDeviceID[device.id], serverURL: serverURL)
        }
    }

    // MARK: - Home geofences and excursions (see ADR-0014, ADR-0016)

    /// Marks a geofence as one LibrePaw manages as a "home", so it can be
    /// found again regardless of whether the owner renames it in Traccar.
    /// Kept as `"scentrailHome"` (the app's name before its rename to
    /// LibrePaw) rather than renamed to match: this is a stored attribute
    /// on geofences that may already exist on a live server, renaming it
    /// would silently stop recognizing every home created by an
    /// already-deployed build. Purely an internal key, never shown to a
    /// user, so there's no reason it needs to track the product name.
    private static let homeAttributeKey = "scentrailHome"

    func homeGeofences(forPetID petID: Int) async throws -> [HomeGeofence] {
        do {
            let homes = try await homeTraccarGeofences(forPetID: petID)
            return homes.compactMap(Self.homeGeofence(from:))
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    func addHomeGeofence(forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {
        do {
            let area = TraccarGeofenceArea.circleWKT(
                centerLatitude: center.latitude,
                centerLongitude: center.longitude,
                radiusMeters: radiusMeters
            )
            let attributes: [String: JSONValue] = [Self.homeAttributeKey: .bool(true)]
            let created = try await client.createGeofence(name: name, area: area, attributes: attributes)
            try await client.linkGeofence(geofenceId: created.id, toDeviceId: petID)
            await syncGeofenceVisibility(geofenceId: created.id, petID: petID)
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    func updateHomeGeofence(_ homeID: Int, forPetID petID: Int, name: String, center: Coordinate, radiusMeters: Double) async throws {
        do {
            let area = TraccarGeofenceArea.circleWKT(
                centerLatitude: center.latitude,
                centerLongitude: center.longitude,
                radiusMeters: radiusMeters
            )
            let attributes: [String: JSONValue] = [Self.homeAttributeKey: .bool(true)]
            try await client.updateGeofence(id: homeID, name: name, area: area, attributes: attributes)
            await syncGeofenceVisibility(geofenceId: homeID, petID: petID)
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    /// Grants whoever is using LibrePaw right now, plus every user with an
    /// explicit permission link to the pet's device, the same link to this
    /// geofence, linking a geofence to a *device* only controls which
    /// device's crossings generate events for it, it does not by itself
    /// make the geofence visible to any user (confirmed against a live
    /// server; see ADR-0017).
    ///
    /// Both steps are unconditional, not diffed against existing links
    /// first: `POST /api/permissions` for a link that already exists was
    /// confirmed (live server) to just return `204` again rather than
    /// erroring, so there's nothing to protect against by checking first.
    ///
    /// Both are also best-effort, this never throws, and the device link
    /// made just before this is called has already succeeded, which is what
    /// matters for excursion detection; this only affects who can
    /// additionally *see* the home in LibrePaw/Traccar's own UI:
    /// - Granting the current user needs `fetchCurrentUser()`, which only
    ///   needs an ordinary account and works for anyone.
    /// - Granting every other device-permitted user needs
    ///   `fetchPermittedUserIDs(deviceId:)`, which, confirmed against a
    ///   live server, only works for an administrator account; for
    ///   anyone else it fails here every time, silently, which is fine:
    ///   that person still got their own grant above. An admin editing a
    ///   home once (even without changing anything) is what extends it to
    ///   the rest of the household, see ADR-0017.
    private func syncGeofenceVisibility(geofenceId: Int, petID: Int) async {
        let selfID = try? await client.fetchCurrentUser().id
        if let selfID {
            try? await client.linkGeofence(geofenceId: geofenceId, toUserId: selfID)
        }

        if let deviceUserIDs = try? await client.fetchPermittedUserIDs(deviceId: petID) {
            // Skip re-granting whoever we just granted above, confirmed
            // live that immediately re-POSTing the *same* permission can
            // fail with a 400 rather than the idempotent 204 the standalone
            // case returns, so this avoids a pointless, occasionally-noisy
            // duplicate request rather than relying on it being harmless.
            for userID in deviceUserIDs where userID != selfID {
                try? await client.linkGeofence(geofenceId: geofenceId, toUserId: userID)
            }
        }
    }

    func deleteHomeGeofence(_ homeID: Int) async throws {
        do {
            try await client.deleteGeofence(id: homeID)
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    // MARK: - Permissions and pet sharing (see ADR-0017, ADR-0018, ADR-0023)

    func currentUserPermissions() async throws -> AccountPermissions {
        do {
            let user = try await client.fetchCurrentUser()
            return AccountPermissions(
                isAdministrator: user.administrator,
                canManageHomes: user.administrator || !user.readonly,
                canManageDevicePhoto: user.administrator || (!user.readonly && !user.deviceReadonly),
                canViewExcursions: user.administrator || !user.disableReports
            )
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    func sharePet(forPetID petID: Int, withEmail email: String) async throws {
        do {
            let matches = try await client.fetchUsers(keyword: email)
            guard let user = matches.first(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) else {
                throw LibrePawError.unexpected("No Traccar user with that email was found on this server.")
            }
            try await client.linkDevice(deviceId: petID, toUserId: user.id)

            // Best-effort: the caller is already confirmed admin to reach
            // this screen (see ADR-0018), so also grant the new user access
            // to every home already set up for this pet, otherwise they'd
            // see the pet but not its excursions until an admin happened to
            // edit a home (ADR-0017's sync-on-edit).
            if let homes = try? await homeTraccarGeofences(forPetID: petID) {
                for home in homes {
                    try? await client.linkGeofence(geofenceId: home.id, toUserId: user.id)
                }
            }
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion] {
        do {
            let homeGeofences = try await homeTraccarGeofences(forPetID: petID)
            guard !homeGeofences.isEmpty else { return [] }
            let homeIDs = Set(homeGeofences.map(\.id))
            let homes = homeGeofences.compactMap(Self.homeGeofence(from:))

            async let exitEvents = client.fetchEvents(deviceId: petID, from: from, to: to, type: TraccarEvent.EventType.geofenceExit)
            async let enterEvents = client.fetchEvents(deviceId: petID, from: from, to: to, type: TraccarEvent.EventType.geofenceEnter)

            let exits = try await exitEvents.filter { homeIDs.contains($0.geofenceId ?? -1) }
            let enters = try await enterEvents.filter { homeIDs.contains($0.geofenceId ?? -1) }

            let pairs = Self.pairHomeExitsWithEnters(exits: exits, enters: enters)

            // Bounded rather than fully unbounded: a pet with years of
            // history backfilling lifetime stats for the first time could
            // otherwise fire a network request per excursion all at once -
            // fine for a handful, not for a thousand-plus against a small
            // self-hosted server.
            let excursions = try await Self.concurrentMap(pairs, maxConcurrent: 20) { pair in
                try await self.makeExcursion(petID: petID, exit: pair.exit, enter: pair.enter, homes: homes)
            }
            return excursions.sorted { $0.startTime > $1.startTime }
        } catch let error as TraccarError {
            throw error.asLibrePawError
        }
    }

    /// Pairs each home-geofence exit with the next home-geofence enter
    /// chronologically after it, pulled out of `fetchExcursions` so the
    /// pairing itself can be unit tested directly, the same way
    /// `mergeLifetimeStats` is (see its doc comment).
    ///
    /// With multiple homes (ADR-0016), `exits`/`enters` are no longer all
    /// crossings of a single geofence, they're crossings of *any* of the
    /// pet's homes, merged into one timeline. The pairing itself needs no
    /// extra logic for that: an exit is still just paired with whichever
    /// enter comes right after it, regardless of which specific home either
    /// belongs to, so a pet leaving one home and returning via another
    /// becomes one excursion rather than two.
    static func pairHomeExitsWithEnters(
        exits: [TraccarEvent],
        enters: [TraccarEvent]
    ) -> [(exit: TraccarEvent, enter: TraccarEvent?)] {
        let sortedExits = exits.sorted { $0.eventTime < $1.eventTime }
        let sortedEnters = enters.sorted { $0.eventTime < $1.eventTime }

        var pairs: [(exit: TraccarEvent, enter: TraccarEvent?)] = []
        var enterIndex = 0
        for exit in sortedExits {
            while enterIndex < sortedEnters.count, sortedEnters[enterIndex].eventTime <= exit.eventTime {
                enterIndex += 1
            }
            let matchingEnter = enterIndex < sortedEnters.count ? sortedEnters[enterIndex] : nil
            if matchingEnter != nil { enterIndex += 1 }
            pairs.append((exit, matchingEnter))
        }
        return pairs
    }

    /// Extra distance beyond a home's own configured radius that still
    /// counts as "close enough" in `firstHomecomingPause`, see its doc
    /// comment. A flat margin rather than a multiple of the radius: homes
    /// are deliberately small (20-100m, see `SetHomeView`), a flat 100m
    /// comfortably covers both "a few meters short of the boundary" and
    /// ordinary GPS jitter without reaching into unrelated nearby places.
    static let homeProximitySlackMeters: Double = 100

    /// How long the trail has to go quiet right after a near-home position
    /// before `firstHomecomingPause` trusts it as "the device actually
    /// stopped there" rather than a single jittery fix passed through
    /// while still moving (e.g. walking past the house without going in).
    /// Above ordinary GPS reporting intervals (confirmed live: a real
    /// Mictrack reports every one to two minutes while moving), so a gap
    /// this long already means the device stopped reporting, whether
    /// because it went into standby or simply lost signal.
    static let quietGapAfterHomeProximity: TimeInterval = 10 * 60

    /// Only re-fetches excursions that ended after the last cached run -
    /// completed excursions' distance/duration get folded into the persisted
    /// totals once and never recomputed; an ongoing excursion (if any) is
    /// added fresh on top of the cache for display, without being persisted,
    /// since its distance is still growing.
    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats {
        let serverHost = client.serverURL.host ?? ""
        let cached = lifetimeStatsStore.load(forPetID: petID, serverHost: serverHost)

        let recentExcursions = try await fetchExcursions(forPetID: petID, from: cached?.cachedThroughEndTime ?? .distantPast, to: .now)

        let (stats, newCache) = Self.mergeLifetimeStats(cached: cached, recentExcursions: recentExcursions)
        lifetimeStatsStore.save(newCache, forPetID: petID, serverHost: serverHost)
        return stats
    }

    /// Pure accumulation logic, pulled out of `lifetimeExcursionStats` so it
    /// can be unit tested directly with hand-built excursions instead of a
    /// live/mocked server.
    ///
    /// `recentExcursions` is whatever `fetchExcursions` returns, most
    /// recent first (see its `sorted` above), which matters here: this
    /// walks the list newest-to-oldest but always compares each excursion's
    /// end time against the *original* `cached` watermark, not one updated
    /// mid-loop, so an older excursion later in the same batch is never
    /// mistaken for "already counted" just because a newer one just raised
    /// the watermark past it.
    static func mergeLifetimeStats(
        cached: CachedLifetimeStats?,
        recentExcursions: [Excursion]
    ) -> (stats: LifetimeStats, newCache: CachedLifetimeStats) {
        let originalWatermark = cached?.cachedThroughEndTime
        var totalDistance = cached?.totalDistanceMeters ?? 0
        var totalDuration = cached?.totalDurationSeconds ?? 0
        var newWatermark = originalWatermark

        for excursion in recentExcursions {
            guard let endTime = excursion.endTime else { continue }
            if let originalWatermark, endTime <= originalWatermark { continue }
            // Still advances the watermark below, it's genuinely been
            // looked at and shouldn't be re-fetched next time, just not
            // folded into the walking totals.
            if !excursion.isLikelyVehicleTrip {
                totalDistance += excursion.distanceMeters ?? 0
                totalDuration += excursion.duration ?? 0
            }
            if newWatermark == nil || endTime > newWatermark! {
                newWatermark = endTime
            }
        }

        let newCache = CachedLifetimeStats(
            totalDistanceMeters: totalDistance,
            totalDurationSeconds: totalDuration,
            cachedThroughEndTime: newWatermark
        )

        if let ongoing = recentExcursions.first(where: { $0.isOngoing }) {
            totalDistance += ongoing.distanceMeters ?? 0
            totalDuration += Date.now.timeIntervalSince(ongoing.startTime)
        }

        return (LifetimeStats(totalDistanceMeters: totalDistance, totalDurationSeconds: totalDuration), newCache)
    }

    /// `homes` is needed for `firstHomecomingPause`, checked for every
    /// excursion regardless of whether a real enter event exists, every
    /// caller already has it on hand from `fetchExcursions` so there's no
    /// reason to re-derive it per excursion.
    private func makeExcursion(petID: Int, exit: TraccarEvent, enter: TraccarEvent?, homes: [HomeGeofence]) async throws -> Excursion {
        let fetchedEndTime = enter?.eventTime
        let fullTrail = (try? await client.fetchPositionHistory(deviceId: petID, from: exit.eventTime, to: fetchedEndTime ?? Date())) ?? []

        var endTime = fetchedEndTime
        var endHomeID = enter?.geofenceId
        var trail = fullTrail
        // Checked unconditionally, not just while there's no real enter
        // event yet: a real `geofenceEnter` can itself arrive hours late
        // (confirmed live, see ADR-0025) if the device went quiet a short
        // distance short of the boundary and only resumed reporting once
        // it crossed it. `firstHomecomingPause` only ever finds a position
        // at or before `fetchedEndTime` (it searches within this same
        // bounded trail), so it can never push the end *later* than a real
        // enter event, only catch an earlier, truer one.
        if let homecoming = Self.firstHomecomingPause(in: fullTrail, homes: homes),
           Self.shouldPreferHomecoming(homecoming, overFetchedEndTime: fetchedEndTime) {
            endTime = homecoming.fixTime
            endHomeID = homecoming.homeID
            // Bounds the distance/end-coordinate below to the walk-home
            // portion only, not whatever the device reported afterward
            // (e.g. a second walk that starts before Traccar ever logs a
            // real enter event for this one, see ADR-0025).
            trail = fullTrail.filter { $0.fixTime <= homecoming.fixTime }
        }

        let coordinates = trail.sorted { $0.fixTime < $1.fixTime }.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        var distance: Double?
        if coordinates.count > 1 {
            distance = zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + $1.0.distanceMeters(to: $1.1) }
        }

        return Excursion(
            id: exit.id,
            startTime: exit.eventTime,
            endTime: endTime,
            startCoordinate: coordinates.first,
            endCoordinate: coordinates.last,
            distanceMeters: distance,
            startHomeID: exit.geofenceId,
            endHomeID: endHomeID
        )
    }

    /// An excursion otherwise ends only when Traccar logs a `geofenceEnter`
    /// event, which only happens when the device actually transmits a
    /// position crossing the exact boundary. A tracker that drops into a
    /// low-power standby mode a few meters short of it (confirmed live
    /// with a real Mictrack collar) only resumes reporting, and so only
    /// logs that crossing, whenever it next wakes up, which can be hours
    /// later; until then (or forever, if it never crosses the exact
    /// boundary) the excursion would otherwise read as lasting that whole
    /// time, or "Away now" forever, even though the pet was effectively
    /// home the moment it went quiet nearby.
    ///
    /// Looks for the earliest position in the trail that both (a) falls
    /// within `homeProximitySlackMeters` of a home, beyond its own
    /// configured radius, and (b) is followed by at least
    /// `quietGapAfterHomeProximity` of silence, or is simply the last
    /// position reported at all. If found, treats that position's time
    /// and home as the excursion's end, the same outcome as a real enter
    /// event.
    ///
    /// Deliberately keyed to "near home, then quiet" rather than, say,
    /// the device's own live online/offline status (tried first, see
    /// ADR-0025's revision history): `deviceOffline` events turned out
    /// not to be reliably logged for every protocol (confirmed live, zero
    /// in 30 days for two different real devices on this project's own
    /// test server), and the device's *current* status can flip back to
    /// online later (e.g. a second walk starting before any real enter
    /// event arrives), silently reopening an already-"closed" excursion
    /// the next time this re-evaluates. A quiet gap that has already
    /// happened in the historical trail, by contrast, is a fixed fact:
    /// re-running this later, even with a second walk's positions now
    /// appended after it, finds the exact same gap in the exact same
    /// place and reaches the same answer, no local state needs to
    /// remember the decision between calls.
    static func firstHomecomingPause(
        in trail: [TraccarPosition],
        homes: [HomeGeofence],
        proximitySlackMeters: Double = homeProximitySlackMeters,
        minimumQuietGap: TimeInterval = quietGapAfterHomeProximity
    ) -> (fixTime: Date, homeID: Int)? {
        let sorted = trail.sorted { $0.fixTime < $1.fixTime }
        for (index, position) in sorted.enumerated() {
            let coordinate = Coordinate(latitude: position.latitude, longitude: position.longitude)
            guard let nearestHome = homes.first(where: { coordinate.distanceMeters(to: $0.center) <= $0.radiusMeters + proximitySlackMeters }) else {
                continue
            }
            let gap = sorted[(index + 1)...].first.map { $0.fixTime.timeIntervalSince(position.fixTime) } ?? .infinity
            if gap >= minimumQuietGap {
                return (position.fixTime, nearestHome.id)
            }
        }
        return nil
    }

    /// Whether a `firstHomecomingPause` finding should override an
    /// excursion's already-known end. Never on a tie: if it resolves to
    /// the same time as a real `enter` event already did (the common
    /// case, the last position in the bounded trail always qualifies as
    /// a homecoming pause), keep trusting the real event's own home
    /// attribution rather than `firstHomecomingPause`'s "first matching
    /// home in array order" picked via `homes.first(where:)`, which isn't
    /// necessarily the true nearest home despite its `nearestHome` local
    /// variable name, and so could otherwise silently swap in the wrong
    /// home whenever two configured homes' proximity slack zones overlap
    /// (see ADR-0025's revision history). Only a genuinely *earlier*
    /// pause is worth preferring over an already-correct real event.
    static func shouldPreferHomecoming(
        _ homecoming: (fixTime: Date, homeID: Int),
        overFetchedEndTime fetchedEndTime: Date?
    ) -> Bool {
        guard let fetchedEndTime else { return true }
        return homecoming.fixTime < fetchedEndTime
    }

    private func homeTraccarGeofences(forPetID petID: Int) async throws -> [TraccarGeofence] {
        let geofences = try await client.fetchGeofences(deviceId: petID)
        return geofences.filter { $0.attributes[Self.homeAttributeKey]?.boolValue == true }
    }

    private static func homeGeofence(from geofence: TraccarGeofence) -> HomeGeofence? {
        guard let parsed = TraccarGeofenceArea.parseCircle(geofence.area) else { return nil }
        return HomeGeofence(
            id: geofence.id,
            name: geofence.name,
            center: Coordinate(latitude: parsed.latitude, longitude: parsed.longitude),
            radiusMeters: parsed.radiusMeters
        )
    }

    /// Like `elements.map(transform)`, but running at most `maxConcurrent`
    /// transforms at once instead of either one at a time or all of them at
    /// once. Order of `results` matches `elements`.
    static func concurrentMap<Element: Sendable, Result: Sendable>(
        _ elements: [Element],
        maxConcurrent: Int,
        transform: @escaping @Sendable (Element) async throws -> Result
    ) async throws -> [Result] {
        guard !elements.isEmpty else { return [] }

        var results = [Result?](repeating: nil, count: elements.count)
        var nextIndex = 0

        try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            func scheduleNext() {
                guard nextIndex < elements.count else { return }
                let index = nextIndex
                let element = elements[index]
                nextIndex += 1
                group.addTask { (index, try await transform(element)) }
            }

            for _ in 0..<min(maxConcurrent, elements.count) {
                scheduleNext()
            }
            while let (index, result) = try await group.next() {
                results[index] = result
                scheduleNext()
            }
        }

        return results.map { $0! }
    }
}
