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
    /// original request set it, `URLSession` moves it into a stream before
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
// static slot, running them concurrently would race on which handler is active.
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

    @Test("fetchData rejects a same-host URL that downgrades the scheme")
    func fetchDataRejectsSchemeDowngrade() async throws {
        let downgradedURL = URL(string: "http://traccar.example.com/steal-credentials")!

        await #expect(throws: TraccarError.invalidServerURL) {
            try await self.makeClient().fetchData(from: downgradedURL)
        }
    }

    @Test("updateDeviceImage uploads the image, then PUTs the device back whole with only deviceImage changed")
    func updateDeviceImagePreservesEveryOtherField() async throws {
        let requests = LockedArray<URLRequest>()

        // A device with every field Traccar actually stores (see
        // BaseObjectResource/Device.java) populated to something
        // non-default, so a field dropped by the merge would be caught.
        let existingDeviceJSON = """
        {
            "id": 1, "name": "Buddy", "uniqueId": "123456789012345",
            "status": "online", "disabled": false, "lastUpdate": "2026-01-01T00:00:00.000+00:00",
            "positionId": 42, "groupId": 7, "calendarId": 3,
            "phone": "+15551234567", "model": "Mictrack MT710", "contact": "Jane Doe",
            "category": "animal", "expirationTime": null,
            "attributes": {"scentrailHome": true}
        }
        """

        MockURLProtocol.requestHandler = { request in
            requests.append(request)
            guard let url = request.url else { throw TraccarError.invalidServerURL }

            if url.path == "/api/devices/1/image" {
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
                #expect(request.bodyData == Data([0xFF, 0xD8, 0xFF]))
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("device.jpg".utf8))
            } else if url.path == "/api/devices/1", request.httpMethod == nil || request.httpMethod == "GET" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(existingDeviceJSON.utf8))
            } else if url.path == "/api/devices/1", request.httpMethod == "PUT" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, request.bodyData)
            }
            throw TraccarError.invalidServerURL
        }

        try await makeClient().updateDeviceImage(deviceId: 1, imageData: Data([0xFF, 0xD8, 0xFF]), contentType: "image/jpeg")

        let allRequests = requests.values
        #expect(allRequests.count == 3)

        let putRequest = allRequests.last!
        #expect(putRequest.httpMethod == "PUT")
        let putBody = try JSONSerialization.jsonObject(with: putRequest.bodyData) as? [String: Any]

        // Every pre-existing field survives untouched...
        #expect(putBody?["name"] as? String == "Buddy")
        #expect(putBody?["uniqueId"] as? String == "123456789012345")
        #expect(putBody?["phone"] as? String == "+15551234567")
        #expect(putBody?["model"] as? String == "Mictrack MT710")
        #expect(putBody?["contact"] as? String == "Jane Doe")
        #expect(putBody?["groupId"] as? Int == 7)
        #expect(putBody?["calendarId"] as? Int == 3)
        #expect(putBody?["category"] as? String == "animal")

        // ...except attributes, which gained deviceImage without losing what was already there.
        let attributes = putBody?["attributes"] as? [String: Any]
        #expect(attributes?["deviceImage"] as? String == "device.jpg")
        #expect(attributes?["scentrailHome"] as? Bool == true)
    }

    @Test("decodeSocketMessage parses a positions-only update (verified wire format)")
    func decodeSocketMessageParsesPositionsUpdate() async throws {
        let json = """
        {"positions":[{"id":433,"deviceId":1,"fixTime":"2026-11-07T08:10:14.000+00:00",\
        "latitude":51.36412,"longitude":12.39587,"speed":1.6,"course":263.5,"address":null,"attributes":{}}]}
        """
        let update = try await makeClient().decodeSocketMessage(.string(json))

        #expect(update.devices == nil)
        #expect(update.positions?.count == 1)
        #expect(update.positions?.first?.deviceId == 1)
    }

    @Test("decodeSocketMessage parses an empty keep-alive message")
    func decodeSocketMessageParsesKeepAlive() async throws {
        let update = try await makeClient().decodeSocketMessage(.string("{}"))

        #expect(update.devices == nil)
        #expect(update.positions == nil)
    }

    @Test("decodeSocketMessage parses a devices-only update")
    func decodeSocketMessageParsesDevicesUpdate() async throws {
        let json = """
        {"devices":[{"id":1,"name":"Phoebe","uniqueId":"862407068395486","status":"online",\
        "disabled":false,"lastUpdate":null,"positionId":null,"category":"animal","attributes":{}}]}
        """
        let update = try await makeClient().decodeSocketMessage(.string(json))

        #expect(update.positions == nil)
        #expect(update.devices?.first?.name == "Phoebe")
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

    @Test("deleteGeofence sends a DELETE to the geofence's own path with Basic Auth and no body")
    func deleteGeofenceSendsDeleteRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/geofences/42")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic b3duZXJAZXhhbXBsZS5jb206c2VjcmV0")
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await makeClient().deleteGeofence(id: 42)
    }

    @Test("linkGeofence(toUserId:) POSTs a userId/geofenceId permission")
    func linkGeofenceToUserSendsPermission() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/permissions")
            let body = try JSONSerialization.jsonObject(with: request.bodyData) as? [String: Int]
            #expect(body?["userId"] == 7)
            #expect(body?["geofenceId"] == 42)
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await makeClient().linkGeofence(geofenceId: 42, toUserId: 7)
    }

    @Test("fetchPermittedUserIDs(deviceId:) queries with userId=0 and returns the userId of each permission")
    func fetchPermittedUserIDsForDeviceBuildsQueryAndParses() async throws {
        // Uppercase keys deliberately, not a typo: confirmed against a live
        // server that /api/permissions returns raw SQL column names
        // (USERID/DEVICEID), unlike every other camelCase Traccar response -
        // see the doc comment on TraccarPermission. A lowercase fixture here
        // would pass even if TraccarPermission's CodingKeys regressed back
        // to the default (wrong) mapping, since unmatched Int? fields decode
        // as nil instead of throwing.
        let json = """
        [{"USERID": 7, "DEVICEID": 3}, {"USERID": 9, "DEVICEID": 3}]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let queryNames = (components.queryItems ?? []).map(\.name)
            // Order matters here, not just presence: confirmed against a
            // live server that `userId` must come *before* `deviceId` in the
            // URL or Traccar's query builder resolves the wrong (nonexistent)
            // table, see the doc comment on fetchPermittedUserIDs.
            #expect(queryNames == ["userId", "deviceId"])
            let queryValues = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(queryValues["deviceId"] == "3")
            #expect(queryValues["userId"] == "0")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let userIDs = try await makeClient().fetchPermittedUserIDs(deviceId: 3)
        #expect(Set(userIDs) == [7, 9])
    }

    @Test("fetchCurrentUser establishes a cookie session, then GETs /api/session for the User object")
    func fetchCurrentUserUsesCookieSession() async throws {
        let json = """
        {"id": 4, "email": "owner@example.com", "administrator": true}
        """.data(using: .utf8)!
        let requestedPaths = LockedArray<String>()

        MockURLProtocol.requestHandler = { request in
            requestedPaths.append(request.url?.path ?? "")

            if request.url?.path == "/api/session", request.httpMethod == "POST" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            } else {
                #expect(request.url?.path == "/api/session")
                #expect(request.httpMethod == "GET")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, json)
            }
        }

        let user = try await makeClient().fetchCurrentUser()

        #expect(user.id == 4)
        #expect(user.administrator == true)
        #expect(requestedPaths.values == ["/api/session", "/api/session"])
    }

    @Test("fetchUsers(keyword:) sends the keyword as a query parameter")
    func fetchUsersBuildsKeywordQuery() async throws {
        let json = """
        [{"id": 5, "email": "family@example.com", "administrator": false}]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/api/users")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            #expect(components.queryItems?.first(where: { $0.name == "keyword" })?.value == "family@example.com")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let users = try await makeClient().fetchUsers(keyword: "family@example.com")
        #expect(users.first?.id == 5)
    }

    @Test("linkDevice(toUserId:) POSTs a userId/deviceId permission")
    func linkDeviceToUserSendsPermission() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/permissions")
            let body = try JSONSerialization.jsonObject(with: request.bodyData) as? [String: Int]
            #expect(body?["userId"] == 5)
            #expect(body?["deviceId"] == 1)
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await makeClient().linkDevice(deviceId: 1, toUserId: 5)
    }
}
