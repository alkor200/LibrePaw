import Foundation

/// A learned ``BatteryCurve`` and when it was learned, so
/// `TraccarPetRepository.batteryCurve(forPetID:)` only reloads weeks of
/// voltage history once a day rather than on every screen that shows a
/// battery level.
struct CachedBatteryCurve: Codable, Sendable, Equatable {
    /// `nil` when the history had no full discharge yet.
    var curve: BatteryCurve?
    var computedAt: Date
}

protocol BatteryCurveStore: Sendable {
    func load(forPetID petID: Int, serverHost: String) -> CachedBatteryCurve?
    func save(_ cached: CachedBatteryCurve, forPetID petID: Int, serverHost: String)
}

/// Small enough for `UserDefaults`, same reasoning and per-server keying as
/// `UserDefaultsLifetimeStatsStore`.
struct UserDefaultsBatteryCurveStore: BatteryCurveStore, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(forPetID petID: Int, serverHost: String) -> CachedBatteryCurve? {
        guard let data = defaults.data(forKey: key(forPetID: petID, serverHost: serverHost)) else { return nil }
        return try? JSONDecoder().decode(CachedBatteryCurve.self, from: data)
    }

    func save(_ cached: CachedBatteryCurve, forPetID petID: Int, serverHost: String) {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: key(forPetID: petID, serverHost: serverHost))
    }

    private func key(forPetID petID: Int, serverHost: String) -> String {
        // v4: curves cached before they were learned over active time
        // rather than time on the clock, relearned once.
        "org.librepaw.batteryCurve.v4.\(serverHost).\(petID)"
    }
}
