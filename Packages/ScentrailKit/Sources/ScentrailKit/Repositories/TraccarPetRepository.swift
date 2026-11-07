import Foundation
import TraccarKit

/// `PetRepository` backed by a live Traccar server.
struct TraccarPetRepository: PetRepository {
    let client: TraccarClient

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
}
