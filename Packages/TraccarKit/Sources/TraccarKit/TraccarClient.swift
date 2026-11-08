import Foundation

/// A minimal Swift client for the Traccar REST API.
///
/// See ADR-0002 for why Traccar was chosen as the backend, ADR-0006 for why
/// every JSON request uses HTTP Basic Auth rather than a cookie-based
/// session, and ADR-0012 for why media requests are the one exception.
///
/// `TraccarKit` knows nothing about "pets", it only speaks Traccar's own
/// vocabulary (devices, positions) so that it stays reusable outside of
/// LibrePaw.
public actor TraccarClient {
    private let credentials: TraccarCredentials
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Whether a `JSESSIONID` cookie has been established for media and
    /// WebSocket requests (see ADR-0012 and ADR-0013). Established lazily, on
    /// first ``fetchData(from:)`` or ``liveUpdates(reconnectDelay:)`` call.
    private var hasCookieSession = false

    public init(credentials: TraccarCredentials, urlSession: URLSession = .shared) {
        self.credentials = credentials
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = TraccarDateFormatting.decodingStrategy
        self.encoder = JSONEncoder()
    }

    /// The server this client talks to. `credentials` is otherwise private -
    /// this is exposed so callers can build server-relative URLs (e.g. for
    /// Traccar's device media files) without holding credentials themselves.
    public nonisolated var serverURL: URL { credentials.serverURL }

    /// All devices (pets) visible to the authenticated user.
    public func fetchDevices() async throws -> [TraccarDevice] {
        try await getJSON("/api/devices")
    }

    /// The latest known position for each device, optionally filtered to a
    /// specific set of device ids. Passing `nil` returns the latest position
    /// for every device the user can see.
    public func fetchLatestPositions(deviceIds: [Int]? = nil) async throws -> [TraccarPosition] {
        var queryItems: [URLQueryItem] = []
        if let deviceIds {
            queryItems = deviceIds.map { URLQueryItem(name: "deviceId", value: String($0)) }
        }
        return try await getJSON("/api/positions", queryItems: queryItems)
    }

    /// Historical positions for one device within a time range (used to draw
    /// a pet's recent trail on the map).
    public func fetchPositionHistory(deviceId: Int, from: Date, to: Date) async throws -> [TraccarPosition] {
        let queryItems = [
            URLQueryItem(name: "deviceId", value: String(deviceId)),
            URLQueryItem(name: "from", value: TraccarDateFormatting.string(from: from)),
            URLQueryItem(name: "to", value: TraccarDateFormatting.string(from: to))
        ]
        return try await getJSON("/api/positions", queryItems: queryItems)
    }

    /// Geofences visible to the user, optionally filtered to those linked to
    /// one device.
    public func fetchGeofences(deviceId: Int? = nil) async throws -> [TraccarGeofence] {
        var queryItems: [URLQueryItem] = []
        if let deviceId {
            queryItems = [URLQueryItem(name: "deviceId", value: String(deviceId))]
        }
        return try await getJSON("/api/geofences", queryItems: queryItems)
    }

    /// One geofence by id, including its current attributes, used before an
    /// update that must carry forward an attribute (e.g. who created it,
    /// see ADR-0021) the update's own payload isn't changing, since
    /// `updateGeofence` replaces `attributes` wholesale rather than merging.
    public func fetchGeofence(id: Int) async throws -> TraccarGeofence {
        try await getJSON("/api/geofences/\(id)")
    }

    /// Creates a new geofence. Does not link it to any device, follow up
    /// with ``linkGeofence(geofenceId:toDeviceId:)``.
    public func createGeofence(name: String, area: String, attributes: [String: JSONValue]) async throws -> TraccarGeofence {
        try await sendJSON(method: "POST", "/api/geofences", body: NewTraccarGeofence(name: name, area: area, attributes: attributes))
    }

    /// Updates an existing geofence in place (e.g. moving "home" to a new
    /// location keeps the same geofence id, so device links are unaffected).
    public func updateGeofence(id: Int, name: String, area: String, attributes: [String: JSONValue]) async throws {
        let _: TraccarGeofence = try await sendJSON(
            method: "PUT",
            "/api/geofences/\(id)",
            body: UpdatedTraccarGeofence(id: id, name: name, area: area, attributes: attributes)
        )
    }

    /// Links a geofence to a device, so the device's crossings of it
    /// generate `geofenceEnter`/`geofenceExit` events.
    public func linkGeofence(geofenceId: Int, toDeviceId deviceId: Int) async throws {
        try await sendJSONNoContent(method: "POST", "/api/permissions", body: GeofenceDevicePermission(deviceId: deviceId, geofenceId: geofenceId))
    }

    /// Deletes a geofence entirely (e.g. removing one of a pet's several
    /// home areas, see ADR-0016).
    public func deleteGeofence(id: Int) async throws {
        try await sendNoBody(method: "DELETE", "/api/geofences/\(id)")
    }

    /// Links a geofence to a user, so that user can see and manage it -
    /// linking a geofence to a device alone does **not** do this (see
    /// ``linkGeofence(geofenceId:toDeviceId:)`` and ADR-0017).
    public func linkGeofence(geofenceId: Int, toUserId userId: Int) async throws {
        try await sendJSONNoContent(method: "POST", "/api/permissions", body: UserGeofencePermission(userId: userId, geofenceId: geofenceId))
    }

    /// The ids of every user with an explicit permission link to `deviceId`
    /// (`GET /api/permissions?userId=0&deviceId=<id>`, `0` means "any").
    ///
    /// Two separate things confirmed against a live server, both of which
    /// callers must treat this as best-effort for:
    /// - **Requires an administrator account for *any* query shape**,
    ///   `PermissionsService.checkAdmin()` runs unconditionally before even
    ///   looking at the query parameters, so a non-admin gets a `400` (a raw
    ///   Java stack trace as the body, not a JSON error) even asking only
    ///   about their own permissions, see ADR-0017.
    /// - **`userId` must be the *first* query parameter in the URL, even as
    ///   admin.** `?deviceId=<id>&userId=0` throws `Table "TC_DEVICE_USER"
    ///   not found`, a genuine server-side bug on at least one tested
    ///   Traccar version, not a permissions issue (confirmed: same account,
    ///   same query values, only the parameter *order* changed, and the
    ///   failing shape fails identically for an admin). The working table is
    ///   evidently always addressed as `tc_user_<other>`, so Traccar's own
    ///   query builder only resolves it correctly when `userId` precedes the
    ///   other id in the URL, see ADR-0017.
    public func fetchPermittedUserIDs(deviceId: Int) async throws -> [Int] {
        let permissions: [TraccarPermission] = try await getJSON("/api/permissions", queryItems: [
            URLQueryItem(name: "userId", value: "0"),
            URLQueryItem(name: "deviceId", value: String(deviceId))
        ])
        return permissions.compactMap(\.userId)
    }

    /// The currently authenticated user. Resolved via the cookie-session
    /// dance from ADR-0012 (`GET /api/session` after establishing a
    /// cookie), **not** `GET /api/users`, which, confirmed against a live
    /// server, returns an empty array for a non-admin account regardless
    /// of query parameters (even `?userId=<own id>`), rather than returning
    /// "self" as might be assumed; see ADR-0017.
    public func fetchCurrentUser() async throws -> TraccarUser {
        try await ensureCookieSession()

        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw TraccarError.invalidServerURL
        }
        components.path = (components.path as NSString).appendingPathComponent("/api/session")
        guard let url = components.url else {
            throw TraccarError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request)
        let validData = try validated(data, response)
        do {
            return try decoder.decode(TraccarUser.self, from: validData)
        } catch {
            throw TraccarError.decoding(String(describing: error))
        }
    }

    /// Searches Traccar's user list by a keyword matched against name/email
    /// server-side (`GET /api/users?keyword=`). Confirmed against a live
    /// server: for an administrator this searches every user on the server;
    /// for anyone else it returns an empty array regardless of the keyword
    /// (see ``fetchCurrentUser()``'s doc comment and ADR-0017), so this is
    /// only useful when the caller is already known to be an admin (see
    /// ADR-0018).
    public func fetchUsers(keyword: String) async throws -> [TraccarUser] {
        try await getJSON("/api/users", queryItems: [URLQueryItem(name: "keyword", value: keyword)])
    }

    /// Links a user to a device, so that user can see it (see
    /// ``UserDevicePermission`` and ADR-0018).
    public func linkDevice(deviceId: Int, toUserId userId: Int) async throws {
        try await sendJSONNoContent(method: "POST", "/api/permissions", body: UserDevicePermission(userId: userId, deviceId: deviceId))
    }

    /// Historical events for one device in a time range, filtered to a
    /// single event type (Traccar's `type` query parameter accepts multiple
    /// values, but callers here only ever need one at a time).
    public func fetchEvents(deviceId: Int, from: Date, to: Date, type: String) async throws -> [TraccarEvent] {
        let queryItems = [
            URLQueryItem(name: "deviceId", value: String(deviceId)),
            URLQueryItem(name: "from", value: TraccarDateFormatting.string(from: from)),
            URLQueryItem(name: "to", value: TraccarDateFormatting.string(from: to)),
            URLQueryItem(name: "type", value: type)
        ]
        return try await getJSON("/api/reports/events", queryItems: queryItems)
    }

    /// Sets a device's photo: uploads the image bytes, then points its
    /// `deviceImage` attribute at the result.
    ///
    /// Traccar's upload endpoint (`POST /api/devices/{id}/image`) only
    /// stores the file and hands back its filename, nothing links it to the
    /// device until a follow-up write (confirmed against Traccar's own
    /// `DeviceResource` and the official web client's `DevicePage`, which
    /// does exactly this two-step dance, see ADR-0011).
    ///
    /// That follow-up merges into the device's *raw* JSON rather than going
    /// through ``TraccarDevice`` (which only models the fields LibrePaw
    /// otherwise needs): `PUT /api/devices/{id}` replaces every column on
    /// the server (confirmed against Traccar's `BaseObjectResource`, which
    /// deserializes the body and writes it with `Columns.Exclude("id")`), so
    /// omitting a field Traccar stores, `phone`, `model`, `contact`,
    /// `groupId`, `calendarId`, `expirationTime`, would silently blank it
    /// out. Round-tripping the untouched raw object avoids that regardless
    /// of which fields exist on a given server version.
    public func updateDeviceImage(deviceId: Int, imageData: Data, contentType: String) async throws {
        let filename = try await uploadDeviceImage(deviceId: deviceId, imageData: imageData, contentType: contentType)
        try await mergeDeviceAttribute(deviceId: deviceId, key: "deviceImage", stringValue: filename)
    }

    private func uploadDeviceImage(deviceId: Int, imageData: Data, contentType: String) async throws -> String {
        var request = URLRequest(url: try makeURL("/api/devices/\(deviceId)/image"))
        request.httpMethod = "POST"
        request.setValue(credentials.basicAuthHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        let (data, response) = try await perform(request)
        let validData = try validated(data, response)
        guard let filename = String(data: validData, encoding: .utf8), !filename.isEmpty else {
            throw TraccarError.decoding("Image upload response was not the expected filename string.")
        }
        return filename
    }

    private func mergeDeviceAttribute(deviceId: Int, key: String, stringValue: String) async throws {
        let url = try makeURL("/api/devices/\(deviceId)")

        var getRequest = URLRequest(url: url)
        getRequest.setValue(credentials.basicAuthHeaderValue, forHTTPHeaderField: "Authorization")
        getRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (deviceData, deviceResponse) = try await perform(getRequest)
        let validDeviceData = try validated(deviceData, deviceResponse)

        guard var deviceObject = try JSONSerialization.jsonObject(with: validDeviceData) as? [String: Any] else {
            throw TraccarError.decoding("Device JSON was not an object.")
        }
        var attributes = deviceObject["attributes"] as? [String: Any] ?? [:]
        attributes[key] = stringValue
        deviceObject["attributes"] = attributes

        var putRequest = URLRequest(url: url)
        putRequest.httpMethod = "PUT"
        putRequest.setValue(credentials.basicAuthHeaderValue, forHTTPHeaderField: "Authorization")
        putRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        putRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        putRequest.httpBody = try JSONSerialization.data(withJSONObject: deviceObject)

        let (putData, putResponse) = try await perform(putRequest)
        _ = try validated(putData, putResponse)
    }

    private func makeURL(_ path: String) throws -> URL {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw TraccarError.invalidServerURL
        }
        components.path = (components.path as NSString).appendingPathComponent(path)
        guard let url = components.url else {
            throw TraccarError.invalidServerURL
        }
        return url
    }

    /// Fetches raw bytes (e.g. a device image under `/api/media/...`) from
    /// this server. `url` must be on the same host as this client's
    /// `serverURL`, credentials are never sent elsewhere.
    ///
    /// Unlike every other endpoint, Traccar's media files ignore HTTP Basic
    /// Auth entirely and require a cookie-based session (verified against a
    /// live server, see ADR-0012). This method establishes one lazily, on
    /// first use, and transparently re-establishes it once if it has expired.
    public func fetchData(from url: URL) async throws -> Data {
        guard url.host == credentials.serverURL.host, url.scheme == credentials.serverURL.scheme else {
            throw TraccarError.invalidServerURL
        }

        try await ensureCookieSession()

        // Traccar reuses the same filename ("device.jpg") on every photo
        // upload, so the URL never changes when a photo is replaced, a
        // cached response here would keep serving the old image bytes
        // indefinitely.
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await perform(request)
        if response.statusCode == 401 {
            hasCookieSession = false
            try await ensureCookieSession()
            let (retryData, retryResponse) = try await perform(request)
            return try validated(retryData, retryResponse)
        }
        return try validated(data, response)
    }

    /// A continuous stream of live device/position updates from Traccar's
    /// WebSocket feed (`/api/socket`). Like media requests, this endpoint
    /// ignores Basic Auth and needs a cookie session (verified against a live
    /// server, see ADR-0012 and ADR-0013).
    ///
    /// Transient connection drops are retried automatically after
    /// `reconnectDelay`, so this stream only finishes (with an error) when
    /// the initial cookie session itself cannot be established, or when the
    /// caller cancels consumption of the stream.
    public nonisolated func liveUpdates(reconnectDelay: Duration = .seconds(5)) -> AsyncThrowingStream<TraccarSocketUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        try await self.ensureCookieSession()
                        let webSocketTask = try await self.makeWebSocketTask()
                        webSocketTask.resume()
                        defer { webSocketTask.cancel(with: .goingAway, reason: nil) }

                        while !Task.isCancelled {
                            let message = try await webSocketTask.receive()
                            if let update = try? await self.decodeSocketMessage(message) {
                                continuation.yield(update)
                            }
                        }
                    } catch {
                        if Task.isCancelled { break }
                        await self.invalidateCookieSession()
                        try? await Task.sleep(for: reconnectDelay)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func invalidateCookieSession() {
        hasCookieSession = false
    }

    private func makeWebSocketTask() throws -> URLSessionWebSocketTask {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw TraccarError.invalidServerURL
        }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = (components.path as NSString).appendingPathComponent("/api/socket")
        guard let url = components.url else {
            throw TraccarError.invalidServerURL
        }
        return urlSession.webSocketTask(with: url)
    }

    /// Internal (not `private`) so it can be unit tested directly, a real
    /// `URLSessionWebSocketTask` can't be driven through `MockURLProtocol`,
    /// so this is the one piece of ``liveUpdates(reconnectDelay:)`` that gets
    /// dedicated test coverage; the rest was verified against a live server.
    func decodeSocketMessage(_ message: URLSessionWebSocketTask.Message) throws -> TraccarSocketUpdate {
        let data: Data
        switch message {
        case .data(let messageData):
            data = messageData
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            data = Data()
        }
        return try decoder.decode(TraccarSocketUpdate.self, from: data)
    }

    // MARK: - Cookie session (media and WebSocket, see ADR-0012)

    private func ensureCookieSession() async throws {
        guard !hasCookieSession else { return }

        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw TraccarError.invalidServerURL
        }
        components.path = (components.path as NSString).appendingPathComponent("/api/session")
        guard let url = components.url else {
            throw TraccarError.invalidServerURL
        }

        var formComponents = URLComponents()
        formComponents.queryItems = [
            URLQueryItem(name: "email", value: credentials.email),
            URLQueryItem(name: "password", value: credentials.password)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((formComponents.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await perform(request)
        _ = try validated(data, response)
        hasCookieSession = true
    }

    // MARK: - Transport

    private func getJSON<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw TraccarError.invalidServerURL
        }
        components.path = (components.path as NSString).appendingPathComponent(path)
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw TraccarError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.setValue(credentials.basicAuthHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request)
        let validData = try validated(data, response)

        do {
            return try decoder.decode(T.self, from: validData)
        } catch {
            throw TraccarError.decoding(String(describing: error))
        }
    }

    private func sendJSON<Body: Encodable, T: Decodable>(method: String, _ path: String, body: Body) async throws -> T {
        let data = try await send(method: method, path, body: body)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw TraccarError.decoding(String(describing: error))
        }
    }

    private func sendJSONNoContent<Body: Encodable>(method: String, _ path: String, body: Body) async throws {
        _ = try await send(method: method, path, body: body)
    }

    private func sendNoBody(method: String, _ path: String) async throws {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw TraccarError.invalidServerURL
        }
        components.path = (components.path as NSString).appendingPathComponent(path)
        guard let url = components.url else {
            throw TraccarError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.basicAuthHeaderValue, forHTTPHeaderField: "Authorization")

        let (data, response) = try await perform(request)
        _ = try validated(data, response)
    }

    private func send<Body: Encodable>(method: String, _ path: String, body: Body) async throws -> Data {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw TraccarError.invalidServerURL
        }
        components.path = (components.path as NSString).appendingPathComponent(path)
        guard let url = components.url else {
            throw TraccarError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.basicAuthHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await perform(request)
        return try validated(data, response)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if request.httpMethod == nil {
            request.httpMethod = "GET"
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw TraccarError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TraccarError.transport("No HTTP response received.")
        }
        return (data, httpResponse)
    }

    private func validated(_ data: Data, _ response: HTTPURLResponse) throws -> Data {
        switch response.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw TraccarError.invalidCredentials
        default:
            throw TraccarError.server(statusCode: response.statusCode)
        }
    }
}
