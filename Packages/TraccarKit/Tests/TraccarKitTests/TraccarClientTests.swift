import Foundation
import Testing
@testable import TraccarKit

// Serialized because all tests share `MockURLProtocol.requestHandler`, a single
// static slot — running them concurrently would race on which handler is active.
@Suite("TraccarClient", .serialized)
struct TraccarClientTests {
    private func makeClient() -> TraccarClient {
        let credentials = TraccarCredentials(
            serverURL: URL(string: "https://traccar.example.com")!,
            email: "owner@example.com",
            password: "secret"
        )
        return TraccarClient(credentials: credentials, urlSession: MockURLProtocol.makeSession())
    }

    @Test("fetchDevices decodes a device list and sends Basic Auth")
    func fetchDevicesDecodesAndAuthenticates() async throws {
        let json = """
        [
            {
                "id": 1,
                "name": "Buddy",
                "uniqueId": "collar-001",
                "status": "online",
                "disabled": false,
                "lastUpdate": "2026-01-15T10:30:00.123+0000",
                "positionId": 42,
                "category": "dog",
                "attributes": {}
            }
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/api/devices")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic b3duZXJAZXhhbXBsZS5jb206c2VjcmV0")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let devices = try await makeClient().fetchDevices()

        #expect(devices.count == 1)
        #expect(devices[0].name == "Buddy")
        #expect(devices[0].status == .online)
        #expect(devices[0].lastUpdate != nil)
    }

    @Test("A 401 response surfaces as invalidCredentials")
    func unauthorizedMapsToInvalidCredentials() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await #expect(throws: TraccarError.invalidCredentials) {
            try await self.makeClient().fetchDevices()
        }
    }

    @Test("An unexpected status code surfaces as .server")
    func serverErrorIsPropagated() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await #expect(throws: TraccarError.server(statusCode: 500)) {
            try await self.makeClient().fetchDevices()
        }
    }

    @Test("fetchLatestPositions attaches one deviceId query item per id")
    func fetchLatestPositionsBuildsQueryItems() async throws {
        let json = "[]".data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let deviceIdValues = components.queryItems?.filter { $0.name == "deviceId" }.compactMap(\.value) ?? []
            #expect(deviceIdValues.sorted() == ["1", "2"])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let positions = try await makeClient().fetchLatestPositions(deviceIds: [1, 2])
        #expect(positions.isEmpty)
    }
}
