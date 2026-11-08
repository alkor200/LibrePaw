import Foundation

/// What `TraccarPetRepository` persists between launches so lifetime stats
/// don't need to be recomputed from a pet's entire excursion history on
/// every load, only from whatever's new since `cachedThroughEndTime`.
struct CachedLifetimeStats: Codable, Sendable, Equatable {
    var totalDistanceMeters: Double
    var totalDurationSeconds: TimeInterval
    /// End time of the most recent *completed* excursion folded into the
    /// totals above. `nil` means nothing has been cached yet.
    var cachedThroughEndTime: Date?
}

protocol LifetimeStatsStore: Sendable {
    func load(forPetID petID: Int, serverHost: String) -> CachedLifetimeStats?
    func save(_ stats: CachedLifetimeStats, forPetID petID: Int, serverHost: String)
}

/// `UserDefaults` is a reasonable home for this: it's a small, non-sensitive
/// running total, not credentials (those go through `CredentialStore`/
/// Keychain instead).
///
/// Keyed by server host as well as device id: Traccar device ids are small
/// sequential integers, unique only *within* one server, without the host
/// in the key, logging into a second server where some other pet happens to
/// reuse the same id would show that pet's cached totals bleeding into this
/// one's.
struct UserDefaultsLifetimeStatsStore: LifetimeStatsStore, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(forPetID petID: Int, serverHost: String) -> CachedLifetimeStats? {
        guard let data = defaults.data(forKey: key(forPetID: petID, serverHost: serverHost)) else { return nil }
        return try? JSONDecoder().decode(CachedLifetimeStats.self, from: data)
    }

    func save(_ stats: CachedLifetimeStats, forPetID petID: Int, serverHost: String) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: key(forPetID: petID, serverHost: serverHost))
    }

    private func key(forPetID petID: Int, serverHost: String) -> String {
        "org.scentrail.lifetimeStats.\(serverHost).\(petID)"
    }
}
