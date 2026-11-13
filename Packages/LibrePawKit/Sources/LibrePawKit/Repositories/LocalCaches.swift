import Foundation

/// Everything `TraccarPetRepository` derives from one account's server
/// data and keeps on the device between launches: cached excursions
/// (start/end coordinates, home ids) and lifetime totals.
///
/// Neither store's keys include the account, only server host and pet
/// id, so whatever one account cached would otherwise surface for the
/// next account to sign in to the same server, including excursions
/// against homes only the first account could see.
enum LocalCaches {
    /// Every key prefix any version of either store has ever written,
    /// earlier, no longer read key versions included.
    static let keyPrefixes = [
        "org.librepaw.excursionsCache.",
        "org.librepaw.lifetimeStats."
    ]

    static func clearAll(in defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where keyPrefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
