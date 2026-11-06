import Foundation
import Testing
import TraccarKit
@testable import ScentrailKit

@Suite("PetMapping")
struct PetMappingTests {
    private let serverURL = URL(string: "https://traccar.example.com")!

    @Test("Maps a Traccar device and its latest position into a Pet")
    func mapsDeviceWithPosition() {
        let lastUpdate = Date(timeIntervalSince1970: 1_700_000_000)
        let fixTime = Date(timeIntervalSince1970: 1_700_000_100)

        let device = TraccarDevice(
            id: 7,
            name: "Buddy",
            uniqueId: "collar-007",
            status: .online,
            disabled: false,
            lastUpdate: lastUpdate,
            positionId: 99,
            category: "dog",
            attributes: [:]
        )
        let position = TraccarPosition(
            id: 99,
            deviceId: 7,
            fixTime: fixTime,
            latitude: 52.5,
            longitude: 13.4,
            speed: 10, // knots
            course: 180,
            address: "Berlin",
            attributes: ["batteryLevel": .double(76)]
        )

        let pet = PetMapping.pet(from: device, latestPosition: position, serverURL: serverURL)

        #expect(pet.id == 7)
        #expect(pet.name == "Buddy")
        #expect(pet.species == "dog")
        #expect(pet.status == .online)
        #expect(pet.lastSeenAt == lastUpdate)
        #expect(pet.lastPosition?.coordinate.latitude == 52.5)
        #expect(pet.lastPosition?.batteryLevelPercent == 76)
        // 10 knots == 18.52 km/h
        #expect(pet.lastPosition?.speedKilometersPerHour.isApproximatelyEqual(to: 18.52) == true)
    }

    @Test("A device with no reported position maps to a Pet with no lastPosition")
    func mapsDeviceWithoutPosition() {
        let device = TraccarDevice(
            id: 1,
            name: "Whiskers",
            uniqueId: "collar-001",
            status: .unknown,
            disabled: false,
            lastUpdate: nil,
            positionId: nil,
            category: nil,
            attributes: [:]
        )

        let pet = PetMapping.pet(from: device, latestPosition: nil, serverURL: serverURL)

        #expect(pet.lastPosition == nil)
        #expect(pet.species == nil)
        #expect(pet.status == .unknown)
    }

    @Test("A deviceImage attribute maps to a photo URL under /api/media/<uniqueId>/<filename>")
    func mapsDeviceImageAttributeToPhotoURL() {
        let device = TraccarDevice(
            id: 7,
            name: "Buddy",
            uniqueId: "collar-007",
            status: .online,
            disabled: false,
            lastUpdate: nil,
            positionId: nil,
            category: "dog",
            attributes: ["deviceImage": .string("buddy.jpg")]
        )

        let pet = PetMapping.pet(from: device, latestPosition: nil, serverURL: serverURL)

        #expect(pet.photoURL?.absoluteString == "https://traccar.example.com/api/media/collar-007/buddy.jpg")
    }

    @Test("No deviceImage attribute maps to a nil photo URL")
    func noDeviceImageAttributeMapsToNilPhotoURL() {
        let device = TraccarDevice(
            id: 7,
            name: "Buddy",
            uniqueId: "collar-007",
            status: .online,
            disabled: false,
            lastUpdate: nil,
            positionId: nil,
            category: "dog",
            attributes: [:]
        )

        let pet = PetMapping.pet(from: device, latestPosition: nil, serverURL: serverURL)

        #expect(pet.photoURL == nil)
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double = 0.001) -> Bool {
        abs(self - other) <= tolerance
    }
}
