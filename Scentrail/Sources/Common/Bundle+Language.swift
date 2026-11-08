import Foundation

/// Holds the `.lproj` bundle to resolve strings from when the in-app
/// language override (see ADR-0022) is active, `nil` for "follow the
/// device's own language" (the default).
///
/// An earlier version of this made `Bundle.main` resolve the override by
/// swapping its runtime class (`object_setClass`) to one overriding
/// `localizedString(forKey:value:table:)`. `Bundle` is a class cluster
/// with private subclasses and internal state a naive `object_setClass`
/// swap doesn't account for, not something safe to impersonate this way.
/// This instead just loads the target language's own `.lproj` bundle
/// directly and calls its `localizedString` method, no class trickery, no
/// shared mutable runtime state to corrupt.
enum LocalizationBundle {
    nonisolated(unsafe) private static var override: Bundle?

    /// `languageCode` is e.g. `"de"`, matching an `.lproj` folder name (or
    /// a String Catalog's language id) in the main bundle. `nil` restores
    /// normal device-language resolution.
    static func setLanguageOverride(_ languageCode: String?) {
        guard let languageCode,
              let path = Bundle.main.path(forResource: languageCode, ofType: "lproj") else {
            override = nil
            return
        }
        override = Bundle(path: path)
    }

    /// The bundle `localized(_:_:)` should resolve strings from right now.
    static var current: Bundle {
        override ?? Bundle.main
    }
}
