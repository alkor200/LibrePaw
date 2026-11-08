import SwiftUI

/// Scentrail's brand color tokens, backed by light/dark asset-catalog
/// colorsets of the same name (`Assets.xcassets`) - see each case's doc
/// comment for the exact hex pair. `AccentColor` itself is set to
/// `appPrimary`'s values, so every `.tint`-driven control (buttons, the
/// tab bar, `NavigationLink` chevrons, …) already follows this palette
/// without needing any of these explicitly.
///
/// Declared on `ShapeStyle where Self == Color` rather than directly on
/// `Color`: that's what makes the leading-dot shorthand
/// (`.foregroundStyle(.appText)`, `.background(.appSurface, in: ...)`) resolve
/// - a plain `extension Color { static let … }` only supports the fully
/// qualified `Color.appText` form.
extension ShapeStyle where Self == Color {
    /// Page background. `#F5F8F4` light / `#171D1A` dark.
    static var appBackground: Color { Color("AppBackground") }
    /// Card/row surface drawn on top of ``appBackground``. `#FFFFFF` light /
    /// `#252E29` dark.
    static var appSurface: Color { Color("AppSurface") }
    /// Brand interactive color; matches `AccentColor`. Same value in both
    /// appearances: `#A8C5AE`.
    static var appPrimary: Color { Color("AppPrimary") }
    /// Stronger variant of ``appPrimary`` for when it needs more contrast
    /// than the soft brand tone gives (e.g. text/icons that must stay
    /// legible on a light surface). `#668B70` light / `#85AA8D` dark.
    static var appPrimaryDark: Color { Color("AppPrimaryDark") }
    /// Primary text. `#29352D` light / `#EFF5EF` dark.
    static var appText: Color { Color("AppText") }
    /// Secondary/caption text. `#78847B` light / `#A9B7AC` dark.
    static var appSecondaryText: Color { Color("AppSecondaryText") }
    /// Hairlines, dividers, strokes. `#E2EAE2` light / `#37423B` dark.
    static var appBorder: Color { Color("AppBorder") }
}
