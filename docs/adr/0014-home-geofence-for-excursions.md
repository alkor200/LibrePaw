# 14. Derive excursions from a home geofence, not Traccar's generic trip report

## Status

Accepted

## Context

The ask: a list of "excursions" — periods from when a pet leaves home until
it returns — distance, duration, each. Traccar does have a built-in
`GET /api/reports/trips` endpoint that already computes trips server-side
from motion/stop detection. Tested against a live server before building
anything on top of it:

```
Trip 1: 18.7m over 5 minutes  (avg speed 0.12 km/h)
Trip 2: 47.4m over 1 minute
Trip 3: 60.6m over 1 minute
```

This is GPS/motion jitter, not real walks — Traccar's trip detection is
tuned for vehicles, far too sensitive to a collar's movement pattern at
rest. Using it directly would produce dozens of meaningless "excursions" a
day, and a single real walk with a couple of sniff-stops could fragment
into several trip-report entries instead of being one excursion.

Verified instead: Traccar's **geofence** feature, combined with
`GET /api/reports/events`, gives exactly the "home to home" semantics
wanted, using only existing Traccar primitives:

- `POST /api/geofences` creates a geofence; its `area` field is a WKT-like
  string. Traccar's circle syntax is `CIRCLE (lat lon, radiusMeters)` —
  **latitude first**, confirmed by reading `GeofenceCircle.java`'s own
  `toWkt`/`fromWkt` directly, *not* standard WKT's (X, Y) =
  (longitude, latitude) order. An earlier version of this ADR (and the code)
  got this backwards, "confirmed" only by writing and reading back a
  geofence with our own (consistently wrong) convention — a round-trip that
  passes even when the order is wrong, since both ends agree with each
  other, just not with Traccar's actual geofence evaluation. The bug only
  surfaced once a geofence built this way was tested against real geofence
  membership (a simulated device's positions never registered as "inside,"
  since the geofence had silently landed on the opposite hemisphere).
- `POST /api/permissions` with `{deviceId, geofenceId}` links a geofence to
  a device.
- Crossing a linked geofence generates `geofenceEnter`/`geofenceExit`
  events, readable via `GET /api/reports/events?type=...` — and this
  endpoint, unlike `/api/session`, `/api/media`, and `/api/socket`, uses
  ordinary Basic Auth (confirmed live) — it's a normal JAX-RS resource, not
  one of the special-cased ones from ADR-0006/0012/0013.

## Decision

**Setting home** (`PetRepository.setHomeGeofence(forPetID:center:radiusMeters:)`):
creates (or moves, if one already exists) a circular geofence, linked to the
pet's device. Per the explicit request, there is no draggable map pin —
`SetHomeView` just uses the owner's current location (`LocationService`)
and a radius slider, so the whole setup is "stand at home, tap Save."

The geofence is identified by a custom boolean attribute,
`attributes.scentrailHome = true`, rather than by name — robust against the
owner renaming it in Traccar's own UI, and avoids colliding with any other
geofences they might already have for unrelated reasons.

**Reading excursions** (`PetRepository.fetchExcursions(forPetID:from:to:)`):
fetches `geofenceExit` and `geofenceEnter` events separately (simpler and
unambiguous vs. relying on uncertain multi-value query-parameter encoding
for a combined request), filters both to the home geofence's id, then pairs
each exit with the next enter after it via a single linear merge pass. An
exit with no following enter yet means the pet is currently away — modeled
as `Excursion.endTime == nil` (`isOngoing`), not an error. Distance per
excursion is computed the same way as the pet detail page's daily-distance
stat: summing `Coordinate.distanceMeters(to:)` over the position history
for that time window.

## Consequences

- No new Scentrail-side storage: "home" and the excursion history both live
  entirely in Traccar, as a geofence and its events — consistent with
  Scentrail's "thin client" scope (ADR-0002).
- One owner-driven setup step (`Set Home`) is required before any
  excursions appear; `ExcursionsView` explains this in its empty state
  rather than failing silently.
- `fetchExcursions` makes one additional `fetchPositionHistory` call per
  excursion (to compute its distance/trail bounds) on top of the two event
  queries — acceptable since excursions are a bounded, low-frequency list
  (at most a handful per day for a pet), not something fetched at polling
  frequency.
- Moving home (calling `setHomeGeofence` again) updates the existing
  geofence **in place** (same id) rather than deleting and recreating it —
  deliberate, so the device-geofence permission link set up the first time
  doesn't need to be redone.
- This correctly handles a pet that pauses mid-walk (sniffing, resting) —
  since excursion boundaries are purely "left the home circle" / "back in
  the home circle," not motion-based, a long stationary pause during a walk
  no longer fragments it into multiple entries the way the native trips
  report would.
