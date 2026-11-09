import Foundation

/// What `TraccarPetRepository` persists between calls so `fetchExcursions`
/// doesn't re-fetch position history and rerun `firstHomecomingPause` for
/// an excursion it has already closed and cached, only for whatever closed
/// since `cachedThroughEndTime`, or hasn't been computed at all yet.
///
/// Deliberately never invalidated by a later home change (moving, resizing,
/// renaming, or deleting a home): a closed excursion happened against
/// whichever home configuration existed at the time, re-deriving it against
/// a home the owner has since moved or deleted would make history itself
/// look like it changed. See ADR-0026.
struct CachedExcursions: Codable, Sendable, Equatable {
    var excursions: [Excursion]
    /// The earliest point this cache has *contiguous* coverage from, up to
    /// `cachedThroughEndTime`. Needed because the very first call to ever
    /// populate this cache might ask for a narrow, recent range (e.g.
    /// `PetDetailViewModel.loadTodaysExcursions()`'s `from: startOfDay`),
    /// not the full history. Without tracking this separately, a later,
    /// wider request (e.g. `ExcursionsView`'s own window) would see a
    /// non-nil `cachedThroughEndTime` and wrongly assume everything before
    /// it was already cached, silently hiding every excursion older than
    /// that first narrow query forever (confirmed live: this exact bug,
    /// before `coveredFrom` existed). A request whose own `from` is
    /// earlier than this must always be fetched live in full, regardless
    /// of `cachedThroughEndTime`. `nil` means nothing has been cached yet.
    var coveredFrom: Date?
    /// End time of the most recent *closed* excursion folded in here.
    /// `nil` means nothing has been cached yet. An ongoing excursion
    /// (`endTime == nil`) never advances this and is never itself stored,
    /// its distance/end are still changing.
    var cachedThroughEndTime: Date?
}

protocol ExcursionCacheStore: Sendable {
    func load(forPetID petID: Int, serverHost: String) -> CachedExcursions?
    func save(_ cached: CachedExcursions, forPetID petID: Int, serverHost: String)
    func clear(forPetID petID: Int, serverHost: String)
}

/// `UserDefaults` is a reasonable home for this, same reasoning as
/// `UserDefaultsLifetimeStatsStore`: a non-sensitive, locally-derived
/// cache, not credentials. Keyed by server host as well as device id for
/// the same reason too (Traccar device ids are only unique within one
/// server).
struct UserDefaultsExcursionCacheStore: ExcursionCacheStore, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(forPetID petID: Int, serverHost: String) -> CachedExcursions? {
        guard let data = defaults.data(forKey: key(forPetID: petID, serverHost: serverHost)) else { return nil }
        return try? JSONDecoder().decode(CachedExcursions.self, from: data)
    }

    func save(_ cached: CachedExcursions, forPetID petID: Int, serverHost: String) {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: key(forPetID: petID, serverHost: serverHost))
    }

    func clear(forPetID petID: Int, serverHost: String) {
        defaults.removeObject(forKey: key(forPetID: petID, serverHost: serverHost))
    }

    private func key(forPetID petID: Int, serverHost: String) -> String {
        "org.librepaw.excursionsCache.\(serverHost).\(petID)"
    }
}
