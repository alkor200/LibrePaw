import Foundation

/// Looks up `key` in the current language override's `.lproj` bundle (see
/// `LocalizationBundle`), falling back to the key itself if there's no
/// translation. `args`, if given, are substituted into the result via
/// `String(format:)`, matching the `%@`/`%lld` placeholders used throughout
/// `Localizable.xcstrings`.
///
/// Deliberately not `String(localized:)`: confirmed live, with the Settings
/// language override active, that it (and even its own `locale:` parameter)
/// keeps returning the English string for a String Catalog-backed key, only
/// the legacy `Bundle.localizedString(forKey:value:table:)` API actually
/// respects a specific bundle's own language (see ADR-0022). This exists
/// for exactly the strings SwiftUI's own
/// `Text(LocalizedStringKey)`/`.environment(\.locale)` mechanism can't
/// cover: ones built as plain `String`s outside a view's body, in a view
/// model.
func localized(_ key: String, _ args: CVarArg...) -> String {
    let template = LocalizationBundle.current.localizedString(forKey: key, value: nil, table: nil)
    guard !args.isEmpty else { return template }
    return String(format: template, arguments: args)
}
