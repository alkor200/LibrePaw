import Foundation

/// A minimal, stateless Swift client for the Traccar REST API.
///
/// See ADR-0002 for why Traccar was chosen as the backend and ADR-0006 for
/// why this client uses HTTP Basic Auth on every request instead of a
/// cookie-based session.
///
/// `TraccarKit` knows nothing about "pets" — it only speaks Traccar's own
/// vocabulary (devices, positions, users) so that it stays reusable outside
/// of Scentrail.
public actor TraccarClient {
    private let credentials: TraccarCredentials
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    public init(credentials: TraccarCredentials, urlSession: URLSession = .shared) {
        self.credentials = credentials
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = TraccarDateFormatting.decodingStrategy
    }

    /// Validates the stored credentials against the server and returns the
    /// authenticated user's profile. Call this once after login; it is not
    /// required before other calls, since every request is independently
    /// authenticated.
    public func fetchCurrentUser() async throws -> TraccarUser {
        try await get("/api/session")
    }

    /// All devices (pets) visible to the authenticated user.
    public func fetchDevices() async throws -> [TraccarDevice] {
        try await get("/api/devices")
    }

    /// The latest known position for each device, optionally filtered to a
    /// specific set of device ids. Passing `nil` returns the latest position
    /// for every device the user can see.
    public func fetchLatestPositions(deviceIds: [Int]? = nil) async throws -> [TraccarPosition] {
        var queryItems: [URLQueryItem] = []
        if let deviceIds {
            queryItems = deviceIds.map { URLQueryItem(name: "deviceId", value: String($0)) }
        }
        return try await get("/api/positions", queryItems: queryItems)
    }

    /// Historical positions for one device within a time range (used to draw
    /// a pet's recent trail on the map).
    public func fetchPositionHistory(deviceId: Int, from: Date, to: Date) async throws -> [TraccarPosition] {
        let queryItems = [
            URLQueryItem(name: "deviceId", value: String(deviceId)),
            URLQueryItem(name: "from", value: TraccarDateFormatting.string(from: from)),
            URLQueryItem(name: "to", value: TraccarDateFormatting.string(from: to))
        ]
        return try await get("/api/positions", queryItems: queryItems)
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
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
        request.httpMethod = "GET"
        request.setValue(credentials.basicAuthHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw TraccarError.invalidCredentials
        default:
            throw TraccarError.server(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw TraccarError.decoding(String(describing: error))
        }
    }
}
