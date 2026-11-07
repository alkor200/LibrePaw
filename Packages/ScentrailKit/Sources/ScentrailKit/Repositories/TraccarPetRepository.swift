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
            throw error.asScentrailError
        }
    }

    func fetchTrail(forPetID petID: Int, from: Date, to: Date) async throws -> [PetPosition] {
        do {
            let positions = try await client.fetchPositionHistory(deviceId: petID, from: from, to: to)
            return positions
                .sorted { $0.fixTime < $1.fixTime }
                .map(PetMapping.position(from:))
        } catch let error as TraccarError {
            throw error.asScentrailError
        }
    }

    func fetchPhoto(for pet: Pet) async throws -> Data? {
        guard let photoURL = pet.photoURL else { return nil }
        do {
            return try await client.fetchData(from: photoURL)
        } catch let error as TraccarError {
            throw error.asScentrailError
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
                    continuation.finish(throwing: error.asScentrailError)
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

    // MARK: - Home geofence and excursions (see ADR-0014)

    /// Marks a geofence as the one Scentrail manages as "home", so it can be
    /// found again regardless of whether the owner renames it in Traccar.
    private static let homeAttributeKey = "scentrailHome"
    private static let homeGeofenceName = "Home (Scentrail)"

    func homeGeofence(forPetID petID: Int) async throws -> HomeGeofence? {
        do {
            guard let home = try await homeTraccarGeofence(forPetID: petID) else { return nil }
            return Self.homeGeofence(from: home)
        } catch let error as TraccarError {
            throw error.asScentrailError
        }
    }

    func setHomeGeofence(forPetID petID: Int, center: Coordinate, radiusMeters: Double) async throws {
        do {
            let area = TraccarGeofenceArea.circleWKT(
                centerLatitude: center.latitude,
                centerLongitude: center.longitude,
                radiusMeters: radiusMeters
            )
            let attributes = [Self.homeAttributeKey: true]

            if let existing = try await homeTraccarGeofence(forPetID: petID) {
                try await client.updateGeofence(id: existing.id, name: Self.homeGeofenceName, area: area, attributes: attributes)
            } else {
                let created = try await client.createGeofence(name: Self.homeGeofenceName, area: area, attributes: attributes)
                try await client.linkGeofence(geofenceId: created.id, toDeviceId: petID)
            }
        } catch let error as TraccarError {
            throw error.asScentrailError
        }
    }

    func fetchExcursions(forPetID petID: Int, from: Date, to: Date) async throws -> [Excursion] {
        do {
            guard let home = try await homeTraccarGeofence(forPetID: petID) else { return [] }

            async let exitEvents = client.fetchEvents(deviceId: petID, from: from, to: to, type: TraccarEvent.EventType.geofenceExit)
            async let enterEvents = client.fetchEvents(deviceId: petID, from: from, to: to, type: TraccarEvent.EventType.geofenceEnter)

            let exits = try await exitEvents
                .filter { $0.geofenceId == home.id }
                .sorted { $0.eventTime < $1.eventTime }
            let enters = try await enterEvents
                .filter { $0.geofenceId == home.id }
                .sorted { $0.eventTime < $1.eventTime }

            var excursions: [Excursion] = []
            var enterIndex = 0
            for exit in exits {
                while enterIndex < enters.count, enters[enterIndex].eventTime <= exit.eventTime {
                    enterIndex += 1
                }
                let matchingEnter = enterIndex < enters.count ? enters[enterIndex] : nil
                if matchingEnter != nil { enterIndex += 1 }

                excursions.append(try await makeExcursion(petID: petID, exit: exit, enter: matchingEnter))
            }
            return excursions.sorted { $0.startTime > $1.startTime }
        } catch let error as TraccarError {
            throw error.asScentrailError
        }
    }

    /// Only re-fetches excursions that ended after the last cached run —
    /// completed excursions' distance/duration get folded into the persisted
    /// totals once and never recomputed; an ongoing excursion (if any) is
    /// added fresh on top of the cache for display, without being persisted,
    /// since its distance is still growing.
    func lifetimeExcursionStats(forPetID petID: Int) async throws -> LifetimeStats {
        let cached = lifetimeStatsStore.load(forPetID: petID)
        let watermark = cached?.cachedThroughEndTime

        let recentExcursions = try await fetchExcursions(forPetID: petID, from: watermark ?? .distantPast, to: .now)

        var totalDistance = cached?.totalDistanceMeters ?? 0
        var totalDuration = cached?.totalDurationSeconds ?? 0
        var newWatermark = watermark

        for excursion in recentExcursions {
            guard let endTime = excursion.endTime else { continue }
            if let newWatermark, endTime <= newWatermark { continue }
            totalDistance += excursion.distanceMeters ?? 0
            totalDuration += excursion.duration ?? 0
            newWatermark = endTime
        }

        lifetimeStatsStore.save(
            CachedLifetimeStats(totalDistanceMeters: totalDistance, totalDurationSeconds: totalDuration, cachedThroughEndTime: newWatermark),
            forPetID: petID
        )

        if let ongoing = recentExcursions.first(where: { $0.isOngoing }) {
            totalDistance += ongoing.distanceMeters ?? 0
            totalDuration += Date.now.timeIntervalSince(ongoing.startTime)
        }

        return LifetimeStats(totalDistanceMeters: totalDistance, totalDurationSeconds: totalDuration)
    }

    private func makeExcursion(petID: Int, exit: TraccarEvent, enter: TraccarEvent?) async throws -> Excursion {
        let endTime = enter?.eventTime
        let trail = (try? await client.fetchPositionHistory(deviceId: petID, from: exit.eventTime, to: endTime ?? Date())) ?? []
        let coordinates = trail.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }

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
            distanceMeters: distance
        )
    }

    private func homeTraccarGeofence(forPetID petID: Int) async throws -> TraccarGeofence? {
        let geofences = try await client.fetchGeofences(deviceId: petID)
        return geofences.first { $0.attributes[Self.homeAttributeKey]?.boolValue == true }
    }

    private static func homeGeofence(from geofence: TraccarGeofence) -> HomeGeofence? {
        guard let parsed = TraccarGeofenceArea.parseCircle(geofence.area) else { return nil }
        return HomeGeofence(
            center: Coordinate(latitude: parsed.latitude, longitude: parsed.longitude),
            radiusMeters: parsed.radiusMeters
        )
    }
}
