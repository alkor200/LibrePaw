# Scentrail

Scentrail is an open source iOS app for keeping an eye on your pets' GPS
trackers. It is a native SwiftUI client for [Traccar](https://www.traccar.org/),
a self-hostable, open source GPS tracking platform. Scentrail does not run
its own backend, and is not affiliated with the Traccar project.

> **Status:** early MVP. See [Roadmap](#roadmap) for what's deliberately out
> of scope today.

## Features

- Sign in to your own Traccar server.
- A map of every pet's last known position, plus your own location.
- See all your pets (Traccar "devices") with their live online/offline status.
- Per-pet detail view with speed, battery level and address.
- **Find Pet**: an AirTag-style compass arrow + distance pointing you toward
  a pet.
- Pet avatars on the map: a photo if you set one (see
  [Setting a pet photo](#setting-a-pet-photo)), otherwise a paw icon.
- **Excursions**: set one or more of a pet's home locations (current
  location + a radius, right from the app) and see a list of trips away
  from home and back, with distance and duration. A trip can start at one
  home and end at another (e.g. "Home → Cabin") if that's where the pet's
  positions actually show it going.
- **Trail**: every excursion in an adjustable window (24 hours by default,
  up to 30 days) drawn on the map at once, each walk in its own color, tap
  one to open its excursion detail.
- **Share a pet** with another Traccar account by email, right from the
  app (admin accounts only, see
  [Sharing a pet](#sharing-a-pet-and-multiple-household-accounts) below).
- Live position updates over Traccar's WebSocket feed, and a switchable
  standard/satellite/hybrid map layer.
- English and German, switchable in Settings, defaulting to automatic
  (follows the device's own language setting, see
  [ADR-0022](docs/adr/0022-german-language-option.md)).

## Requirements

- A running Traccar server (self-hosted or hosted by a third party) with at
  least one device configured for your pet's tracker.
- Xcode 16 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Getting started

```sh
git clone https://github.com/<your-fork>/Scentrail.git
cd Scentrail
cp Scentrail/Config/Local.xcconfig.example Scentrail/Config/Local.xcconfig
# edit Local.xcconfig and fill in your own DEVELOPMENT_TEAM (see ADR-0015)
xcodegen generate
open Scentrail.xcodeproj
```

To run on a real device (not just the simulator), you'll need to fill in
`DEVELOPMENT_TEAM` in `Local.xcconfig` with your own Apple Development team
id. Run `security find-identity -v -p codesigning` to find it, or look it up
under Xcode → Settings → Accounts. This file is gitignored and, unlike an
environment variable, survives every `xcodegen generate` (see ADR-0015).

Build and run the `Scentrail` scheme on an iOS 17+ simulator or device, then
sign in with your Traccar server's address and your account's email/password.

Whenever you add, remove, or move source files, or change `project.yml`,
re-run `xcodegen generate` before building.

### Setting a pet photo

Use Traccar's own device image upload: open the device in Traccar's web UI →
**Edit Device** → upload an image. Scentrail reads it back via Traccar's
`deviceImage` attribute and `/api/media/...` endpoint, no Scentrail-specific
setup needed. Devices without a photo show a paw icon instead.

### Setting a pet's home locations

Open a pet's detail screen → **`<Pet>`'s Homes** → **Add Home**, give it a
name, stand (or drag the map to) where you want it to be, pick a radius,
and save. Scentrail creates a Traccar geofence linked to that pet's
device, visible in Traccar's own web UI too. Add as many as you like (e.g.
"Home" and "Cabin"); swipe to delete one, or tap it to move/rename it.
Excursions only start appearing once at least one home is set.

Any account can do this, but **who else can see the result depends on
whether you're a Traccar administrator**: Traccar has no way for a
non-admin to make a geofence visible to anyone besides themselves (see
[ADR-0017](docs/adr/0017-geofence-user-permissions-for-multi-user-households.md)).
Scentrail shows which case applies right on the Homes screen:

- **Administrator**: a home you add is visible to everyone with access to
  that pet, and so are the excursions it generates.
- **Non-admin**: a home you add, and the excursions it generates, is
  only ever visible to you. If a home should apply to the whole household,
  have the admin account add it instead
  (see [ADR-0019](docs/adr/0019-reenable-non-admin-homes-with-a-visibility-notice.md)).

As a non-admin, you can also view homes someone else (an admin) shared
with you, but not edit or delete them, those show a lock icon in the list.
Only the account that created a home, or an admin, can change it
(see [ADR-0021](docs/adr/0021-client-side-home-ownership-for-non-admin-edit-delete.md)).

### Sharing a pet and multiple household accounts

If more than one person in your household uses Scentrail against the same
Traccar server, the server's **admin account** should be the one adding
homes and sharing pets. From a pet's detail screen, tap **Share `<Pet>`**,
enter the other person's Traccar account email, and they'll see the pet
(and any homes already set up for it) in their own copy of Scentrail
immediately. This is also admin-only, and for the same reason as above:
Traccar requires admin rights to grant another account access to anything
(see [ADR-0018](docs/adr/0018-admin-only-homes-and-pet-sharing.md)).

## Color scheme

Scentrail uses a small set of brand color tokens, each a light/dark pair
in `Assets.xcassets` and exposed in code via `Color.appX` (see
`Scentrail/Sources/Common/Color+Theme.swift`). `AccentColor` itself
matches `Primary`, so most buttons, the tab bar tint, and similar
`.tint`-driven controls follow this palette automatically.

| Token | Light | Dark |
| --- | --- | --- |
| Background | `#F5F8F4` | `#171D1A` |
| Surface | `#FFFFFF` | `#252E29` |
| Primary | `#A8C5AE` | `#A8C5AE` |
| Primary Dark | `#668B70` | `#85AA8D` |
| Text | `#29352D` | `#EFF5EF` |
| Secondary Text | `#78847B` | `#A9B7AC` |
| Border | `#E2EAE2` | `#37423B` |

The app icon's background uses `Primary` as well.

## Running tests

The domain and networking layers are plain Swift packages and can be tested
without Xcode:

```sh
cd Packages/TraccarKit && swift test
cd Packages/ScentrailKit && swift test
```

App-layer tests (view models) run via the `ScentrailTests` target in Xcode
(`Cmd+U`), since they depend on the app module.

## Architecture

Scentrail is split into three layers (see [`docs/adr`](docs/adr) for the full
reasoning behind each decision):

```
Scentrail (app target)         SwiftUI views + @Observable view models (MVVM)
   │
   ▼
ScentrailKit (local package)   Domain models (Pet, PetPosition), repository
                                protocols, Keychain-backed auth
   │
   ▼
TraccarKit (local package)     A standalone Traccar REST + WebSocket client
```

- **`TraccarKit`** knows nothing about "pets", it is a general-purpose,
  reusable Swift client for Traccar's REST API (devices, positions) and its
  WebSocket live feed. It could be extracted into its own repository
  without changes.
- **`ScentrailKit`** is the app's domain and data layer: it maps Traccar's
  "devices" onto Scentrail's own `Pet` model, defines the `PetRepository` and
  `AuthenticationService` protocols, and stores credentials in the Keychain.
- **`Scentrail`** (the app target) contains only SwiftUI views and view
  models, grouped by feature (`Authentication`, `PetList`, `Map`,
  `PetDetail`, `Find`, `Home`, `Excursions`, `Settings`). It depends on
  `ScentrailKit` only, never
  directly on `TraccarKit`. It's also the only place that touches
  `CoreLocation` (for the user's own position/heading); the distance and
  bearing math itself lives in `ScentrailKit` as plain functions on
  `Coordinate`.

Key decisions, each recorded as an ADR:

| ADR | Decision |
| --- | --- |
| [0001](docs/adr/0001-record-architecture-decisions.md) | Record architecture decisions |
| [0002](docs/adr/0002-use-traccar-as-backend.md) | Use Traccar as the tracking backend |
| [0003](docs/adr/0003-ios-platform-and-ui-framework.md) | Target iOS 17+ with SwiftUI only |
| [0004](docs/adr/0004-project-generation-with-xcodegen.md) | Generate the Xcode project with XcodeGen |
| [0005](docs/adr/0005-modular-architecture-with-local-swift-packages.md) | Modular architecture with local Swift packages |
| [0006](docs/adr/0006-http-basic-auth-and-rest-polling.md) | HTTP Basic Auth for REST (polling superseded by 0013) |
| [0007](docs/adr/0007-keychain-credential-storage.md) | Store server credentials in the Keychain |
| [0008](docs/adr/0008-no-device-location-access-in-mvp.md) | No device location access in the MVP (superseded by 0010) |
| [0009](docs/adr/0009-manual-dependency-injection.md) | Manual dependency injection |
| [0010](docs/adr/0010-device-location-for-distance-and-find-pet.md) | Device location for distance display and "Find Pet" |
| [0011](docs/adr/0011-pet-avatar-from-traccar-photo-attribute.md) | Pet avatar from Traccar's built-in device image |
| [0012](docs/adr/0012-cookie-session-for-media-requests.md) | Use a cookie session for media requests only |
| [0013](docs/adr/0013-websocket-live-updates.md) | Live updates via Traccar's WebSocket feed |
| [0014](docs/adr/0014-home-geofence-for-excursions.md) | Derive excursions from a home geofence |
| [0015](docs/adr/0015-per-developer-signing-config.md) | Per-developer signing config via a gitignored xcconfig file |
| [0016](docs/adr/0016-multiple-home-geofences-per-pet.md) | Support multiple home geofences per pet |
| [0017](docs/adr/0017-geofence-user-permissions-for-multi-user-households.md) | Grant explicit user permissions when creating or editing a home geofence (non-admin editing superseded by 0018) |
| [0018](docs/adr/0018-admin-only-homes-and-pet-sharing.md) | Restrict adding homes and sharing a pet to administrator accounts (homes part superseded by 0019; pet sharing still admin-only) |
| [0019](docs/adr/0019-reenable-non-admin-homes-with-a-visibility-notice.md) | Re-enable home management for non-admin accounts, with an in-app visibility notice |
| [0020](docs/adr/0020-trail-aggregates-excursions-over-an-adjustable-window.md) | "Trail" aggregates excursions over an adjustable window, replacing "Today's Trail" |
| [0021](docs/adr/0021-client-side-home-ownership-for-non-admin-edit-delete.md) | Track home ownership client-side, restrict non-admin edit/delete to the creator |
| [0022](docs/adr/0022-german-language-option.md) | In-app German language option, defaulting to the device's own setting |

## Roadmap

Deliberately out of scope for the current MVP (see the ADRs above for why):

- Geofences and push notifications.
- In-app photo upload (today, use Traccar's own "Edit Device" image upload).
- Breed info, vet records, and other pet-care data unrelated to tracking.

Contributions toward any of these are welcome, please open an issue to
discuss the approach first, especially if it touches an existing ADR.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Scentrail is available under the [MIT License](LICENSE).
