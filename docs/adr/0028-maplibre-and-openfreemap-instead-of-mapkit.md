# 28. Replace MapKit with MapLibre Native and OpenFreeMap

## Status

Accepted.

## Context

ADR-0003 chose SwiftUI's native `Map` view (MapKit) as the maps framework
for a greenfield app with no legacy constraints. MapKit itself isn't a
third-party dependency, it's an Apple framework, but its tile data comes
from Apple's own closed map service.

The question of how large a rewrite it would be to move to a free/libre
map stack instead came up directly. A survey of the app's MapKit usage
found the real blocker was never the code, `Map`/`Annotation`/`MapCircle`/
`MapPolyline` all have close equivalents elsewhere, but the tile-data
source: this project deliberately has zero required third-party accounts,
and `LibrePawKit` has no CoreLocation/MapKit dependency at all (see
ADR-0010). Most free/open map tile providers (MapTiler, Stadia, even
`tile.openstreetmap.org` for anything beyond light/demo use) still
require signing up for an API key, which would have reintroduced exactly
the kind of required external account this app has avoided everywhere
else.

[OpenFreeMap](https://openfreemap.org) was found to be a genuine
exception: free vector tiles with no API key, no account, and no
published rate limit on its public instance, MIT-licensed, and fully
self-hostable if the public instance ever goes away. [MapLibre
Native](https://github.com/maplibre/maplibre-native) (via
[MapLibreSwiftUI](https://github.com/maplibre/swiftui-dsl), a SwiftUI DSL
over it) is the open-source fork of what used to be Mapbox GL Native, and
is the renderer OpenFreeMap's styles are built for.

A trial conversion was built on a separate branch
(`experiment/maplibre-openfreemap`) to evaluate feasibility and visual
quality before committing to the switch, covering every screen that used
`Map`: `PetMapView`, `TrailView`, `ExcursionDetailView`, and `SetHomeView`.

## Decision

Switch from MapKit's SwiftUI `Map` to MapLibre Native (via
`MapLibreSwiftUI`/`MapLibreSwiftDSL`) rendering OpenFreeMap's vector
tiles, across all four map screens.

Specifics worth recording, each one a real bug or gap found and fixed
during the trial, not just a style swap:

- **Style**: OpenFreeMap's "liberty" style in light mode, "fiord" in dark
  mode (not OpenFreeMap's plain "dark" style, which felt too stark a jump
  in practice; "fiord" is a softer, muted dark style closer to Apple
  Maps' own dark mode), switched via `OpenFreeMapStyle.url(for:)` reading
  `\.colorScheme`.
- **Fitting the camera to a single point is a real bug, not just an edge
  case**: `.showcase(shapeCollection:edgePadding:)` fitting bounds to
  exactly one coordinate is a zero-size bounding box, which stalled
  MapLibre's render loop entirely (confirmed live: every tile request got
  cancelled within 200ms of launch and none ever retried, the map stayed
  on a flat background color forever). `PetMapView.fitCameraToAllPets()`,
  `TrailView.fitCameraToAllTrails()`, and
  `ExcursionDetailView.fitCameraToTrail()` all special-case a single
  coordinate with `.center(_:zoom:)` instead.
- **Pins are pre-rendered, not live SwiftUI views**: MapLibre's
  `SymbolStyleLayer` takes a `UIImage` per feature, not a SwiftUI view the
  way MapKit's `Annotation` did, so `PetAnnotationView` (shared with the
  pet list and pet detail, so pins look consistent everywhere) is
  rasterized once per pet via `ImageRenderer` and fed in as a
  `petId`-keyed `iconImage` mapping. An empty mapping dictionary crashes
  MapLibre's style engine outright, so a fallback icon always fills in
  until the real photo loads. The render has to pad the captured view
  (`.padding(6)`) or its `.shadow(radius:)` gets hard-clipped at the
  image's own bounds.
- **No native full-bleed behavior**: unlike MapKit's `Map`, MapLibre's
  `MapView` (a plain `UIViewControllerRepresentable`) doesn't extend
  under the nav bar/tab bar for free, it needs an explicit
  `.ignoresSafeArea()`, with the nav bar title removed entirely and
  MapLibre's own ornaments (logo, attribution, compass) repositioned via
  `.mapContentInset(...)` using the real device safe-area inset (read via
  `GeometryReader`, not a guessed flat constant) so they land relative to
  the tab bar correctly on an actual device, not just the simulator.
- **No user-location dot by default**: `showsUserLocation` has no
  DSL-level modifier yet, set via the library's own documented
  `.unsafeMapViewControllerModifier` escape hatch.
- **Circles are in screen pixels, not meters**: MapLibre's circle-radius
  style property doesn't stay the correct ground size across zoom levels
  the way MapKit's `MapCircle(center:radius:)` did, so `SetHomeView`'s
  home geofence is now a real polygon approximation
  (`Coordinate.circlePolygon(radiusMeters:)`, a new pure geodesic helper
  in `LibrePawKit`) rather than a `MapCircle`.
- **Long-press has no feature hit-testing**: `onLongPressMapGesture` only
  gives a coordinate, unlike `onTapMapGesture(on:)`. The "navigate to
  this pet" long-press approximates hit-testing by nearest pet within a
  small radius, and presents the nav-app chooser as a
  `confirmationDialog` (always a bottom sheet on iPhone, not anchored to
  the press point the way the old `.contextMenu` was).
- `MapLayerPicker` (switching between Apple's standard/satellite/hybrid
  styles) was removed along with it: OpenFreeMap has no free satellite
  imagery equivalent, so there's nothing left to pick between.

ADR-0003's "Maps: the SwiftUI `Map` view from MapKit" line is superseded
by this decision; everything else in that ADR (deployment target,
SwiftUI-only, Observation, Swift Concurrency) still stands.

## Consequences

- No more Apple-only map dependency: the app no longer relies on Apple's
  closed map tile service, matching the zero-required-third-party-account
  posture the rest of the app already has.
- OpenFreeMap's public instance is donation-funded and run by a single
  maintainer, a meaningfully different reliability profile than Apple's
  infrastructure. If it ever becomes unreliable or goes away, OpenFreeMap
  is MIT-licensed and explicitly designed to be self-hostable, which is
  the fallback, not a vague hope.
- Free satellite/hybrid imagery isn't available the way it was through
  MapKit; `MapLayerPicker` is gone and there's no plan to bring an
  equivalent back without a paid tile provider.
- The app now has one real external Swift Package dependency
  (`MapLibreSwiftUI`, which pulls in `maplibre-gl-native-distribution`),
  the first since ADR-0005 established the local-packages-only
  architecture. Both are MIT-licensed.
- Map pins, routes, and the home geofence are now rendered through a
  from-scratch rendering pipeline (`ShapeSource`/`SymbolStyleLayer`/
  `LineStyleLayer`/`FillStyleLayer`) rather than SwiftUI's declarative
  map content builder, more code to maintain per map screen, in exchange
  for not depending on MapKit's tile service.
