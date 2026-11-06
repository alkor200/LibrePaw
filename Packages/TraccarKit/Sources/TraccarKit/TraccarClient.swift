import Foundation

/// A minimal Swift client for the Traccar REST API.
///
/// See ADR-0002 for why Traccar was chosen as the backend, ADR-0006 for why
/// every JSON request uses HTTP Basic Auth rather than a cookie-based
/// session, and ADR-0012 for why media requests are the one exception.
///
/// `TraccarKit` knows nothing about "pets" — it only speaks Traccar's own
/// vocabulary (devices, positions) so that it stays reusable outside of
/// Scentrail.
public actor TraccarClient {
    private let credentials: TraccarCredentials
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    /// Whether a `JSESSIONID` cookie has been established for media requests
    /// (see ADR-0012). Established lazily, on first ``fetchData(from:)`` call.
    private var hasCookieSession = false

    public init(credentials: TraccarCredentials, urlSession: URLSession = .shared) {
        self.credentials = credentials
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = TraccarDateFormatting.decodingStrategy
    }

    /// The server this client talks to. `credentials` is otherwise private —
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

    /// Fetches raw bytes (e.g. a device image under `/api/media/...`) from
    /// this server. `url` must be on the same host as this client's
    /// `serverURL` — credentials are never sent elsewhere.
    ///
    /// Unlike every other endpoint, Traccar's media files ignore HTTP Basic
    /// Auth entirely and require a cookie-based session (verified against a
    /// live server — see ADR-0012). This method establishes one lazily, on
    /// first use, and transparently re-establishes it once if it has expired.
    public func fetchData(from url: URL) async throws -> Data {
        guard url.host == credentials.serverURL.host else {
            throw TraccarError.invalidServerURL
        }

        try await ensureCookieSession()

        let (data, response) = try await perform(URLRequest(url: url))
        if response.statusCode == 401 {
            hasCookieSession = false
            try await ensureCookieSession()
            let (retryData, retryResponse) = try await perform(URLRequest(url: url))
            return try validated(retryData, retryResponse)
        }
        return try validated(data, response)
    }

    // MARK: - Cookie session (media only — see ADR-0012)

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
