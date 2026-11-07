import Foundation

/// What `TraccarPetRepository` persists between launches so lifetime stats
/// don't need to be recomputed from a pet's entire excursion history on
/// every load — only from whatever's new since `cachedThroughEndTime`.
struct CachedLifetimeStats: Codable, Sendable {
    var totalDistanceMeters: Double
    var totalDurationSeconds: TimeInterval
    /// End time of the most recent *completed* excursion folded into the
    /// totals above. `nil` means nothing has been cached yet.
    var cachedThroughEndTime: Date?
}

protocol LifetimeStatsStore: Sendable {
    func load(forPetID petID: Int) -> CachedLifetimeStats?
    func save(_ stats: CachedLifetimeStats, forPetID petID: Int)
}

/// `UserDefaults` is a reasonable home for this: it's a small, non-sensitive
/// running total, not credentials (those go through `CredentialStore`/
/// Keychain instead).
struct UserDefaultsLifetimeStatsStore: LifetimeStatsStore, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(forPetID petID: Int) -> CachedLifetimeStats? {
        guard let data = defaults.data(forKey: key(forPetID: petID)) else { return nil }
        return try? JSONDecoder().decode(CachedLifetimeStats.self, from: data)
    }

    func save(_ stats: CachedLifetimeStats, forPetID petID: Int) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: key(forPetID: petID))
    }

    private func key(forPetID petID: Int) -> String {
        "org.scentrail.lifetimeStats.\(petID)"
    }
}
