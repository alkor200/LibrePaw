import Foundation

/// The in-app language override (see ADR-0022): `.system` follows the
/// device's own language automatically (the default), `.english`/`.german`
/// force a specific one regardless of device settings, applied via
/// `LocalizationBundle.setLanguageOverride(_:)`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case german = "de"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: localized("Automatic")
        case .english: "English"
        case .german: "Deutsch"
        }
    }

    /// `nil` for `.system`, `LocalizationBundle.setLanguageOverride(nil)`
    /// restores the device's own language resolution.
    var languageCode: String? {
        self == .system ? nil : rawValue
    }

    /// `nil` for `.system` (inherit the environment's own locale rather
    /// than forcing one), passed to `.environment(\.locale)` at the view
    /// root otherwise, this is what actually makes SwiftUI `Text`
    /// literals follow the override (see ADR-0022).
    var locale: Locale? {
        languageCode.map(Locale.init(identifier:))
    }
}

/// Persists the chosen `AppLanguage` and keeps `LocalizationBundle`'s
/// override in sync with it, both at launch and whenever the selection
/// changes.
enum AppLanguageStore {
    private static let userDefaultsKey = "appLanguage"

    static func load() -> AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    static func save(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: userDefaultsKey)
        LocalizationBundle.setLanguageOverride(language.languageCode)
    }

    /// Applies whatever was last saved, call once at app launch before any
    /// UI reads a localized string, the override has to already be in
    /// place by then.
    static func applyStoredOverride() {
        LocalizationBundle.setLanguageOverride(load().languageCode)
    }
}

/// Holds the current `AppLanguage` as `@Observable` state, injected into the
/// environment from `RootView` so any screen (in practice just
/// `SettingsView`) can change it. `RootView` keys its content on
/// `language` with `.id(_:)`, since neither the `.environment(\.locale)`
/// change nor `LocalizationBundle`'s override retroactively re-renders a
/// view model's already-built `String` state, the whole tree needs to be
/// torn down and rebuilt to pick up the new language everywhere at once.
@Observable
@MainActor
final class LanguageSettings {
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            AppLanguageStore.save(language)
        }
    }

    init() {
        language = AppLanguageStore.load()
    }
}
