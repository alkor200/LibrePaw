import SwiftUI

/// The in-app appearance override: `.system` follows the device's own
/// light/dark setting automatically (the default), `.light`/`.dark` force
/// a specific one regardless of device settings, applied via
/// `.preferredColorScheme(_:)` at the view root.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: localized("Automatic")
        case .light: localized("Light")
        case .dark: localized("Dark")
        }
    }

    /// `nil` for `.system`, SwiftUI's own meaning for "follow the device",
    /// passed straight to `.preferredColorScheme(_:)`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Persists the chosen `AppAppearance` across launches.
enum AppAppearanceStore {
    private static let userDefaultsKey = "appAppearance"

    static func load() -> AppAppearance {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
              let appearance = AppAppearance(rawValue: rawValue) else {
            return .system
        }
        return appearance
    }

    static func save(_ appearance: AppAppearance) {
        UserDefaults.standard.set(appearance.rawValue, forKey: userDefaultsKey)
    }
}

/// Holds the current `AppAppearance` as `@Observable` state, injected into
/// the environment from `RootView` so any screen (in practice just
/// `SettingsView`) can change it. Unlike `LanguageSettings`,
/// `.preferredColorScheme(_:)` alone is enough, SwiftUI already propagates
/// a color scheme change to every already-built view on its own, no
/// `.id(_:)`-driven rebuild needed.
@Observable
@MainActor
final class AppearanceSettings {
    var appearance: AppAppearance {
        didSet {
            guard appearance != oldValue else { return }
            AppAppearanceStore.save(appearance)
        }
    }

    init() {
        appearance = AppAppearanceStore.load()
    }
}
