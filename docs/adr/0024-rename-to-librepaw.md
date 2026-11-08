# 24. Rename the app from Scentrail to LibrePaw

## Status

Accepted.

## Context

"Scentrail" already names an existing app, so the project needed a new
name to avoid the conflict. "LibrePaw" was chosen as the replacement.

The rename touches nearly every file: Swift module and type names, the
Xcode project/scheme/target names, the bundle identifier, the Keychain
service string credentials are stored under, every ADR and doc file, and
the German/English string catalog.

Two things were deliberately kept unrenamed, both to avoid breaking
something external to this rename:

- The GitHub repository (`alkor200/Scentrail`) and this local working
  directory stay named `Scentrail`. Only the code, the Xcode project
  structure, and the documentation were renamed. Renaming the repository
  itself was considered and declined, to avoid moving the local checkout
  mid-session and to avoid touching a shared, external resource as part
  of what is otherwise a self-contained code change.
- The Traccar geofence attribute key that marks a geofence as an
  app-managed "home" stayed `"scentrailHome"` rather than becoming
  `"librepawHome"`. This key is already written on every home geofence
  that exists on a live Traccar server from a pre-rename build;
  renaming it would silently stop the app from recognizing any of them.
  It's a purely internal identifier, never shown to a user, so there's
  no branding reason to change it, only a data-compatibility reason not
  to.

## Decision

- Directories: `Scentrail/` → `LibrePaw/`, `ScentrailTests/` →
  `LibrePawTests/`, `ScentrailUITests/` → `LibrePawUITests/`,
  `Packages/ScentrailKit/` → `Packages/LibrePawKit/` (and its nested
  `Sources/ScentrailKit`/`Tests/ScentrailKitTests` likewise).
- Files: `ScentrailApp.swift` → `LibrePawApp.swift`, `ScentrailError.swift`
  → `LibrePawError.swift`, `ScentrailUITests.swift` →
  `LibrePawUITests.swift`.
- `project.yml`: `name`, target names, scheme name, `bundleIdPrefix`
  (`org.scentrail` → `org.librepaw`), `PRODUCT_BUNDLE_IDENTIFIER`
  (`org.scentrail.app` → `org.librepaw.app`), `PRODUCT_NAME`,
  `CFBundleDisplayName`, and every path reference.
- `Package.swift` (the local package formerly named `ScentrailKit`):
  package name, library name, target names.
- `KeychainCredentialStore`'s default service string:
  `org.scentrail.app.session` → `org.librepaw.app.session`. Since the
  bundle id itself changed, existing stored credentials under the old
  identifier are already orphaned regardless, so there is no reason to
  keep the old Keychain service name either, both changes have the same
  one-time "log in again" consequence for an already-installed build.
- Every other `Scentrail`/`scentrail` occurrence (comments, doc
  comments, ADR prose, `README.md`, `CONTRIBUTING.md`, `LICENSE`,
  `.github/workflows/ci.yml`, the string catalog's English keys and
  German values) renamed to `LibrePaw`/`librepaw`, with the two
  exceptions above.
- `README.md`'s `git clone` instructions still point at
  `.../Scentrail.git` and `cd Scentrail`, matching the repository's own
  (unrenamed) name, the one place in the document that isn't describing
  the product.

## Consequences

- An existing install built before this rename has a different bundle
  id afterward, which iOS treats as a different app entirely: the old
  one isn't automatically removed or migrated, and the new one starts
  logged out (Keychain-stored credentials don't carry over, same
  reasoning as the service-name change above). Acceptable, this is an
  early MVP with no production users, confirmed by rebuilding,
  reinstalling, and logging back in against the live test server.
- Already-existing Traccar geofences tagged `scentrailHome` continue to
  be recognized by the app without any migration, confirmed live against
  the test server's existing home geofence after the rename.
- The GitHub repository and the local directory both remain named
  `Scentrail`, a deliberate, visible inconsistency with the renamed
  product, documented here rather than silently left unexplained.
