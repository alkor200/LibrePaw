# 14. Derive excursions from a home geofence, not Traccar's generic trip report

## Status

Accepted

## Context

The ask: a list of "excursions" - periods from when a pet leaves home until
it returns - distance, duration, each. Traccar does have a built-in
`GET /api/reports/trips` endpoint that already computes trips server-side
from motion/stop detection. Tested against a live server before building
anything on top of it:

```
Trip 1: 18.7m over 5 minutes  (avg speed 0.12 km/h)
Trip 2: 47.4m over 1 minute
Trip 3: 60.6m over 1 minute
```

This is GPS/motion jitter, not real walks - Traccar's trip detection is
tuned for vehicles, far too sensitive to a collar's movement pattern at
rest. Using it directly would produce dozens of meaningless "excursions" a
day, and a single real walk with a couple of sniff-stops could fragment
into several trip-report entries instead of being one excursion.

Verified instead: Traccar's **geofence** feature, combined with
`GET /api/reports/events`, gives exactly the "home to home" semantics
wanted, using only existing Traccar primitives:

- `POST /api/geofences` creates a geofence; its `area` field is a WKT-like
  string. Traccar's circle syntax is `CIRCLE (lat lon, radiusMeters)` -
  **latitude first**, confirmed by reading `GeofenceCircle.java`'s own
  `toWkt`/`fromWkt` directly, *not* standard WKT's (X, Y) =
  (longitude, latitude) order. An earlier version of this ADR (and the code)
  got this backwards, "confirmed" only by writing and reading back a
  geofence with our own (consistently wrong) convention - a round-trip that
  passes even when the order is wrong, since both ends agree with each
  other, just not with Traccar's actual geofence evaluation. The bug only
  surfaced once a geofence built this way was tested against real geofence
  membership (a simulated device's positions never registered as "inside,"
  since the geofence had silently landed on the opposite hemisphere).
- `POST /api/permissions` with `{deviceId, geofenceId}` links a geofence to
  a device.
- Crossing a linked geofence generates `geofenceEnter`/`geofenceExit`
  events, readable via `GET /api/reports/events?type=...` - and this
  endpoint, unlike `/api/session`, `/api/media`, and `/api/socket`, uses
  ordinary Basic Auth (confirmed live) - it's a normal JAX-RS resource, not
  one of the special-cased ones from ADR-0006/0012/0013.

## Decision

**Setting home** (`PetRepository.setHomeGeofence(forPetID:center:radiusMeters:)`):
creates (or moves, if one already exists) a circular geofence, linked to the
pet's device. `SetHomeView` ("`<Pet>`'s Home" on screen) shows a full-screen
map with a pin fixed at the center and a radius slider (20–100m - a "home"
geofence realistically never needs to be larger); the owner drags the map
underneath the pin to place or move it, the same interaction Apple Maps uses
for dropping a pin, rather than being limited to wherever they're currently
standing. The pin defaults to the owner's current location only when no home
is set yet.

The geofence is identified by a custom boolean attribute,
`attributes.scentrailHome = true`, rather than by name - robust against the
owner renaming it in Traccar's own UI, and avoids colliding with any other
geofences they might already have for unrelated reasons.

**Reading excursions** (`PetRepository.fetchExcursions(forPetID:from:to:)`):
fetches `geofenceExit` and `geofenceEnter` events separately (simpler and
unambiguous vs. relying on uncertain multi-value query-parameter encoding
for a combined request), filters both to the home geofence's id, then pairs
each exit with the next enter after it via a single linear merge pass. An
exit with no following enter yet means the pet is currently away - modeled
as `Excursion.endTime == nil` (`isOngoing`), not an error. Distance per
excursion is computed the same way as the pet detail page's daily-distance
stat: summing `Coordinate.distanceMeters(to:)` over the position history
for that time window.

## Consequences

- No new Scentrail-side storage: "home" and the excursion history both live
  entirely in Traccar, as a geofence and its events - consistent with
  Scentrail's "thin client" scope (ADR-0002).
- One owner-driven setup step (`Set Home`) is required before any
  excursions appear; `ExcursionsView` explains this in its empty state
  rather than failing silently.
- `fetchExcursions` makes one additional `fetchPositionHistory` call per
  excursion (to compute its distance/trail bounds) on top of the two event
  queries, run concurrently via a `TaskGroup` rather than one at a time. The
  original "acceptable since it's a bounded, low-frequency list" reasoning
  only held for `ExcursionsView`'s 7-day window - `lifetimeExcursionStats`
  (below) can request a pet's *entire* history, where this N+1 pattern would
  otherwise mean one network round trip per excursion ever recorded; running
  them concurrently keeps that from being a serial, one-at-a-time wait, and
  the caching strategy below keeps it from recurring on every load.
- **Lifetime stats** (`PetRepository.lifetimeExcursionStats(forPetID:)`):
  total distance/time away across every excursion a pet has ever taken, for
  the pet detail page's "Total Distance"/"Total Time Away" tiles. Computing
  this from scratch on every load would mean re-fetching and re-summing a
  pet's entire excursion history each time, so completed excursions'
  contributions are folded into a small cache
  (`UserDefaultsLifetimeStatsStore`, keyed by server host *and* device id -
  device ids are only unique within one Traccar server) alongside a
  watermark: the end time of the most recently counted excursion. Each
  subsequent call only re-fetches excursions that ended after that watermark.
  An important subtlety: `fetchExcursions` returns results newest-first, so
  the merge must compare each excursion's end time against the *original*
  watermark captured before the loop starts, never one updated mid-loop -
  comparing against a running watermark let a newer excursion's end time
  make an older excursion later in the same batch look "already counted"
  even on the very first run, silently dropping it (caught and fixed after
  it produced a visibly wrong total against live data; see
  `TraccarPetRepository.mergeLifetimeStats`, which is unit tested directly
  against hand-built excursion lists for exactly this ordering). An ongoing
  excursion's distance/duration is added to the displayed total but never
  persisted into the cache, since it's still growing.
- Moving home (calling `setHomeGeofence` again) updates the existing
  geofence **in place** (same id) rather than deleting and recreating it -
  deliberate, so the device-geofence permission link set up the first time
  doesn't need to be redone.
- This correctly handles a pet that pauses mid-walk (sniffing, resting) -
  since excursion boundaries are purely "left the home circle" / "back in
  the home circle," not motion-based, a long stationary pause during a walk
  no longer fragments it into multiple entries the way the native trips
  report would.
