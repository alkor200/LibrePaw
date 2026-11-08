# 22. In-app German language option, defaulting to the device's own setting

## Status

Accepted.

## Context

Asked for a German language option, with an in-app switch rather than
relying solely on the device's system language, but defaulting to
whatever that system language already is rather than forcing a choice.

Scentrail had no localization infrastructure at all: every string was a
hardcoded English literal, and `Info.plist` declared no
`CFBundleLocalizations`.

Three mechanisms were tried, and tested live rather than assumed, for
making an in-app override actually change what's on screen:

- `String(localized:)`/`String(localized:locale:)`: confirmed, neither
  respects an explicit `locale:` argument nor a `Bundle.main` override
  for a String Catalog-backed lookup. Unsuitable for a custom in-app
  override.
- `Bundle.localizedString(forKey:value:table:)` (the legacy
  Objective-C-era API) called directly on a loaded `.lproj` sub-bundle:
  confirmed to work correctly.
- `.environment(\.locale, Locale(identifier:))`: confirmed to be the one
  mechanism that makes SwiftUI's own `Text(LocalizedStringKey)`/`Label`/
  `.navigationTitle` literal resolution follow an explicit override,
  independent of the device's own language.

## Decision

- `Scentrail/Resources/Localizable.xcstrings`, a hand-authored String
  Catalog covering every user-facing string in the app, English as the
  source language, German as the one translation.
- `AppLanguage` (`.system`/`.english`/`.german`), persisted via
  `AppLanguageStore` (plain `UserDefaults`), exposed to the view tree as
  `LanguageSettings`, an `@Observable` injected from `RootView`.
  `.system` means "follow the device", not a specific locale.
- Two complementary resolution paths, since no single mechanism covers
  both layers of the app:
  - `RootView` applies `.environment(\.locale, ...)` at the root, this
    is what makes `Text`/`Label` literals throughout the view layer
    follow the override.
  - `LocalizationBundle` (in `Bundle+Language.swift`) holds whichever
    `.lproj` bundle the override selects (`nil` for `.system`, meaning
    "ask `Bundle.main`"), and the `localized(_:_:)` helper
    (`Localization.swift`) calls its `localizedString(forKey:value:table:)`
    directly. This is what `ViewModel`s and other computed-`String`
    call sites use, since `String(localized:)` doesn't work for this and
    `LocalizedStringKey` doesn't exist outside SwiftUI's own view layer.
  - An earlier version of `LocalizationBundle` tried to make
    `Bundle.main` itself resolve the override, by swapping its runtime
    class (`object_setClass`) to a subclass overriding
    `localizedString(forKey:value:table:)`. Abandoned: `Bundle` is a
    class cluster with private subclasses and internal state a naive
    `object_setClass` swap doesn't account for, not something safe to
    impersonate this way. Loading the target `.lproj` bundle directly
    avoids the problem entirely, no class trickery, no shared mutable
    runtime state.
- `RootView` keys its whole content on `languageSettings.language` with
  `.id(_:)`. Neither the `.environment(\.locale)` change nor
  `LocalizationBundle`'s override retroactively re-renders a view
  model's already-built `String` state, the whole tree needs a fresh
  identity to pick up the new language everywhere at once, immediately,
  rather than only on views that happen to get re-constructed later.
- `SettingsView` gained a `Picker` (Automatic/English/Deutsch), the two
  language names shown in their own language rather than run through
  `localized(_:)`, they're proper nouns, not meant to translate.

## A crash, and its actual cause

Switching the language live via the picker and then navigating into
`HomesView` reliably crashed with `EXC_BAD_ACCESS`/`SIGSEGV`
(`KERN_INVALID_ADDRESS`), backtrace rooted in
`LocalizedStringKey.resolve` → `NSAttributedString`'s format-string
initializer → `CFStringCreateWithFormatAndArguments` →
`objc_opt_respondsToSelector`, i.e. deep inside Foundation/SwiftUICore's
own string-resolution machinery, not in app code.

Several plausible-looking causes were chased and ruled out along the
way (a `Text(bool ? "a" : "b")` ternary pattern; the `.id(_:)` +
`.environment(\.locale, ...)` combination on `RootView`; a synchronous
state write to `languageSettings.language` racing the picker's own
dismissal), none of which, once isolated and retested on their own,
actually reproduced or fixed the crash.

The real cause: `HomeRow`'s and `SetHomeView`'s radius labels interpolate
an `Int` (`Text("\(Int(home.radiusMeters)) m radius")`), which
`LocalizedStringKey` keys with `%lld`, not `%@`. The catalog's *keys*
were already correctly renamed from `%@ m radius` to `%lld m radius`
during authoring, but the German *translated value text* was left as
`"%@ m Radius"`, a copy-paste leftover from before that rename. At
runtime, the key lookup matched correctly (so the right catalog entry
was found), but formatting then applied an `Int64` argument against a
`%@` (object) format specifier. `CFStringCreateWithFormatAndArguments`
walked that specifier and called `objc_opt_respondsToSelector` on what
it expected to be an object, actually a raw integer value
misinterpreted as a pointer, in practice usually the radius itself (a
crash address of `0x32` for a 50-meter home radius is exactly `50`
reinterpreted as an address). This only reproduced through a *live*
switch (not a device already launched with German as its system
language) because the live path formats a freshly-resolved template
string at that moment, where a cold launch's first render apparently
takes a different, less exposed internal path through the same API for
reasons not further investigated.

Fixed by correcting the two affected catalog entries' German value text
to also use `%lld`, and adding an automated sweep (comparing each
catalog key's format specifiers against every one of its translated
values') run as part of authoring, so a key/value specifier mismatch
like this can't reach the catalog unnoticed again.

## Consequences

- Any future string with a non-`String` interpolation (`Int`, `Double`,
  etc.) needs its catalog value's format specifier to match the key's
  exactly in every language, not just be translated correctly. A
  mismatch here crashes rather than mistranslates, so this needs to be
  checked at authoring time, Xcode's own String Catalog editor would
  normally catch this, hand-authoring the `.xcstrings` JSON directly
  does not.
- `.id(_:)` on `RootView` means a language change tears down and rebuilds
  the entire authenticated app tree at once, including whatever tab and
  navigation state was active. Switching language mid-session resets the
  user back to the first tab. Judged acceptable, this is already a rare
  action (most users pick a language once, if ever) and the alternative,
  leaving ViewModels' already-resolved strings stale until their own view
  happens to re-render, is worse.
