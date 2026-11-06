# Scentrail

Scentrail is an open source iOS app for keeping an eye on your pets' GPS
trackers. It is a native SwiftUI client for [Traccar](https://www.traccar.org/),
a self-hostable, open source GPS tracking platform — Scentrail does not run
its own backend, and is not affiliated with the Traccar project.

> **Status:** early MVP. See [Roadmap](#roadmap) for what's deliberately out
> of scope today.

## Features

- Sign in to your own Traccar server.
- A map of every pet's last known position, plus your own location.
- See all your pets (Traccar "devices") with their live online/offline status.
- Per-pet detail view with today's trail, speed, battery level and address.
- **Find Pet**: an AirTag-style compass arrow + distance pointing you toward
  a pet.
- Pet avatars on the map: a photo if you set one (see
  [Setting a pet photo](#setting-a-pet-photo)), otherwise a paw icon.

## Requirements

- A running Traccar server (self-hosted or hosted by a third party) with at
  least one device configured for your pet's tracker.
- Xcode 16 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Getting started

```sh
git clone https://github.com/<your-fork>/Scentrail.git
cd Scentrail
xcodegen generate
open Scentrail.xcodeproj
```

Build and run the `Scentrail` scheme on an iOS 17+ simulator or device, then
sign in with your Traccar server's address and your account's email/password.

Whenever you add, remove, or move source files, or change `project.yml`,
re-run `xcodegen generate` before building.

### Setting a pet photo

Use Traccar's own device image upload: open the device in Traccar's web UI →
**Edit Device** → upload an image. Scentrail reads it back via Traccar's
`deviceImage` attribute and `/api/media/...` endpoint — no Scentrail-specific
setup needed. Devices without a photo show a paw icon instead.

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
TraccarKit (local package)     A standalone Traccar REST API client
```

- **`TraccarKit`** knows nothing about "pets" — it is a general-purpose,
  reusable Swift client for Traccar's REST API (devices, positions,
  sessions). It could be extracted into its own repository without changes.
- **`ScentrailKit`** is the app's domain and data layer: it maps Traccar's
  "devices" onto Scentrail's own `Pet` model, defines the `PetRepository` and
  `AuthenticationService` protocols, and stores credentials in the Keychain.
- **`Scentrail`** (the app target) contains only SwiftUI views and view
  models, grouped by feature (`Authentication`, `PetList`, `Map`,
  `PetDetail`, `Find`, `Settings`). It depends on `ScentrailKit` only — never
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
| [0006](docs/adr/0006-http-basic-auth-and-rest-polling.md) | HTTP Basic Auth and REST polling |
| [0007](docs/adr/0007-keychain-credential-storage.md) | Store server credentials in the Keychain |
| [0008](docs/adr/0008-no-device-location-access-in-mvp.md) | No device location access in the MVP (superseded by 0010) |
| [0009](docs/adr/0009-manual-dependency-injection.md) | Manual dependency injection |
| [0010](docs/adr/0010-device-location-for-distance-and-find-pet.md) | Device location for distance display and "Find Pet" |
| [0011](docs/adr/0011-pet-avatar-from-traccar-photo-attribute.md) | Pet avatar from Traccar's built-in device image |
| [0012](docs/adr/0012-cookie-session-for-media-requests.md) | Use a cookie session for media requests only |

## Roadmap

Deliberately out of scope for the current MVP (see the ADRs above for why):

- Live updates via Traccar's WebSocket feed (currently REST polling).
- Geofences and push notifications.
- In-app photo upload (today, a pet photo is a manually-set Traccar attribute).
- Breed info, vet records, and other pet-care data unrelated to tracking.

Contributions toward any of these are welcome — please open an issue to
discuss the approach first, especially if it touches an existing ADR.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Scentrail is available under the [MIT License](LICENSE).
