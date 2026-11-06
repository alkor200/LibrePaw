import Foundation
import Testing
@testable import TraccarKit

/// A tiny lock-protected array so `MockURLProtocol`'s `@Sendable` handler
/// closures can record call order across (potentially concurrent) requests.
final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ element: Element) {
        lock.withLock { storage.append(element) }
    }

    var values: [Element] {
        lock.withLock { storage }
    }
}

private extension URLRequest {
    /// `URLProtocol` subclasses often see `httpBody` as `nil` even when the
    /// original request set it — `URLSession` moves it into a stream before
    /// handing the request off. This reads it back from whichever is present.
    var bodyData: Data {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}

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

    @Test("fetchData establishes a cookie session via POST /api/session before fetching media")
    func fetchDataEstablishesCookieSessionFirst() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let mediaURL = URL(string: "https://traccar.example.com/api/media/collar-001/device.jpg")!
        let requestedPaths = LockedArray<String>()

        MockURLProtocol.requestHandler = { request in
            requestedPaths.append(request.url?.path ?? "")

            if request.url?.path == "/api/session" {
                #expect(request.httpMethod == "POST")
                let body = String(data: request.bodyData, encoding: .utf8) ?? ""
                #expect(body.contains("email=owner@example.com"))
                #expect(body.contains("password=secret"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            } else {
                #expect(request.url == mediaURL)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, imageData)
            }
        }

        let data = try await makeClient().fetchData(from: mediaURL)

        #expect(data == imageData)
        #expect(requestedPaths.values == ["/api/session", "/api/media/collar-001/device.jpg"])
    }

    @Test("fetchData rejects URLs on a different host than the server")
    func fetchDataRejectsForeignHosts() async throws {
        let foreignURL = URL(string: "https://evil.example.com/steal-credentials")!

        await #expect(throws: TraccarError.invalidServerURL) {
            try await self.makeClient().fetchData(from: foreignURL)
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
