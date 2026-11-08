# 16. Support multiple home geofences per pet

## Status

Accepted

## Context

ADR-0014 gave each pet exactly one "home": `TraccarPetRepository` looked up
the geofence tagged `attributes.scentrailHome = true` with `.first { ... }`,
and `fetchExcursions` filtered exit/enter events to that single geofence's
id. Owners asked for more than one, e.g. a primary residence and a cabin -
managed from the app, with excursions allowed to start at one and end at
another (a trip from home to the cabin shouldn't need to look like two
separate "left home, never came back" entries).

Checked before building anything: Traccar's geofence↔device link
(`POST /api/permissions`) is already many-to-many, a device can have any
number of geofences linked to it, each firing its own independent
`geofenceEnter`/`geofenceExit` events. Nothing about Traccar itself assumes
"one home per device"; that assumption was only ever in LibrePaw's own
code.

## Decision

- `HomeGeofence` gains `id` and `name`, both already available for free
  from Traccar's own geofence object (`TraccarGeofence.id`/`.name`), so this
  is not new LibrePaw-side storage, just exposing fields that were already
  being fetched and previously discarded.
- `PetRepository.homeGeofence(forPetID:)` → `homeGeofences(forPetID:)`
  returning `[HomeGeofence]`. The old `setHomeGeofence` (create-or-move, one
  implicit home) splits into `addHomeGeofence` (create a new one),
  `updateHomeGeofence(_:name:center:radiusMeters:)` (move/rename an existing
  one *in place*, same geofence id, unchanged from ADR-0014's reasoning for
  why that matters), and a new `deleteHomeGeofence(_:)`, backed by a new
  `TraccarClient.deleteGeofence(id:)` (`DELETE /api/geofences/{id}`, the
  one geofence mutation that was never needed before, since there was never
  a home to remove).
- `fetchExcursions` now fetches *all* of a pet's home geofences and widens
  the exit/enter event filter from one fixed id to the set of all their ids.
  The exit→enter pairing itself needed no new logic: it was already purely
  time-based ("next enter after this exit"), never keyed by which geofence
  either event belonged to, so a pet leaving Home and arriving at Cabin
  pairs into one excursion exactly the same way leaving and returning to the
  same home always did. That pairing step is pulled out into a dedicated
  `TraccarPetRepository.pairHomeExitsWithEnters`, mirroring how
  `mergeLifetimeStats` (ADR-0014) was pulled out of its caller, so it can be
  unit tested directly against hand-built events instead of only through a
  live/mocked server.
- `Excursion` gains `startHomeID`/`endHomeID` (each event's own
  `geofenceId`, already fetched, zero extra requests) so the UI can show
  "Home → Cabin" instead of two identical-looking coordinates when they
  differ. Both default to `nil` so existing call sites (previews, tests)
  didn't need touching.
- App layer: a new `HomesView`/`HomesViewModel` list screen (same
  list-of-rows-with-swipe-to-delete shape as nothing else in this codebase
  yet, but the same *load/error/empty-state* shape as `ExcursionsView`)
  replaces `SetHomeView` as `PetDetailView`'s "`<Pet>`'s Homes" destination.
  `SetHomeView`/`SetHomeViewModel` is repurposed to add-or-edit *one* home -
  given an optional existing `HomeGeofence` (nil means "new") rather than
  fetching "the" home itself on load, since the caller (`HomesView`) already
  has the full list. It also gained a name text field. Adding a home
  presents this as a sheet; editing one pushes it via
  `navigationDestination(for: HomeGeofence.self)`; `HomesView` reloads its
  list in both cases via `.onAppear` rather than `.task`, since it stays
  mounted (just covered) under either presentation style, and `.onAppear`
  reliably re-fires on return from either while `.task` is not guaranteed to
  on a push/pop.
- `ExcursionsView`/`ExcursionDetailView` resolve `startHomeID`/`endHomeID`
  to names (fetched alongside the excursions/trail) and show a "Home →
  Cabin"-style caption only when the two differ from each other, an
  ordinary round trip to the same home shows nothing new.

## Consequences

- **Known limitation, not fixed here**: homes placed close together (or
  overlapping) can fragment one long walk into multiple excursions if its
  route passes near/through a second home that isn't the actual
  destination, the same category of problem ADR-0014's geofence approach
  solved for GPS/motion jitter, reintroduced here by home proximity instead
  of sensor noise. Not addressed in this change (e.g. no minimum-distance
  enforcement between homes); revisit if it turns out to matter in
  practice.
- **Unverified assumption, unlike every claim in ADR-0014**: this change
  assumes Traccar's `DELETE /api/geofences/{id}` also removes the
  geofence's device permission link server-side, rather than leaving an
  orphaned permission row behind. ADR-0014's claims were all confirmed
  against a live server before shipping; this one has not been. Verify
  against a live server before relying on it, and recheck
  `GeofenceResource`/the permissions table server-side if anything looks
  off (e.g. a deleted home's permission still listed).
- Deleting a pet's only remaining home behaves exactly as having never set
  one: `ExcursionsView`'s existing empty state already covers "no home
  set yet," now equally correct for "no home set *anymore*."
- No migration needed for existing single-home setups: the existing
  `Home (LibrePaw)`-named geofence is just one more row in the
  now-plural list the first time `homeGeofences` is called.
