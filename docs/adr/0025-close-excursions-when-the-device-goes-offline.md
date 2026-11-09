# 25. Close an ongoing excursion once the device goes offline

## Status

Accepted.

## Context

A real-world report: a Mictrack collar dropped into its low-power standby
mode a few meters before actually crossing back into its home geofence's
boundary. Traccar's `geofenceEnter` event (the signal ADR-0014's whole
excursion model is built on) only fires when the device transmits a
position that crosses the boundary, so a device that goes quiet just
short of it never sends that final position, the enter event never
fires, and the excursion stayed "Away now" indefinitely even though the
pet was actually home.

This is a gap in Traccar's own event model, not something LibrePaw's
existing exit/enter pairing (`pairHomeExitsWithEnters`) could fix on its
own: there is no enter event to pair against, by definition.

## Decision

- `TraccarClient` gains `fetchDevice(id:)`, confirmed against a live
  server that `GET /api/devices` accepts `?id=` the same way
  `/api/geofences`/`/api/positions` accept `?deviceId=` elsewhere in this
  client.
- `TraccarPetRepository.fetchExcursions(forPetID:from:to:)` now runs one
  more step after pairing exits/enters: if the newest excursion is still
  ongoing, it fetches that device and, if its status is `offline` and its
  `lastUpdate` is after the excursion's start, treats `lastUpdate` as the
  excursion's end, the same outcome as if a `geofenceEnter` event had
  arrived at that moment. `endHomeID` stays `nil`, there's no real event
  to say which home it was.
- Split into two pieces, mirroring how `pairHomeExitsWithEnters` sits
  next to the client-dependent `makeExcursion`: a pure, static
  `closingAbandonedExcursion(in:deviceStatus:deviceLastUpdate:)` holding
  the actual decision/rewrite, unit tested directly (seven cases:
  closes when offline, stays open while online, stays open with no
  `lastUpdate`, ignores a `lastUpdate` older than the excursion itself,
  leaves completed excursions and older excursions untouched, handles an
  empty list), and a thin instance method that fetches the device and
  delegates to it. The `fetchDevice` call is best-effort, same as the
  rest of this feature's error handling, a failure just leaves the
  excursion as it was rather than surfacing an error for what's already
  a secondary correction on top of the real event data.
- Since this lives inside `fetchExcursions` itself, every caller gets it
  for free: `ExcursionsView`'s "Away now" label, the pet detail page's
  "Time Away Today" stat, and `lifetimeExcursionStats` (which now also
  correctly folds a closed-this-way excursion into its persisted total
  instead of leaving it uncounted forever).

## Consequences

- Could not be reproduced end-to-end against the live test server: there
  is no way to inject a GPS position (the device protocol ports are
  firewalled from this environment, and `/api/positions`/events have no
  write endpoint), so a live "exit, then device standby with no enter"
  scenario can't be fabricated on demand. Verified instead by: the seven
  unit tests covering the decision logic directly, a `fetchDevice(id:)`
  test confirming the `?id=` query shape and 401/empty-result handling,
  and a live regression pass confirming `fetchExcursions` still behaves
  correctly (empty result, no crash, no extra network error) for both
  test pets, one with no home set and one with no exit events in its
  window, the two paths most likely to be disturbed by this change.
- One extra `GET /api/devices?id=` request per `fetchExcursions` call,
  but only when the result actually contains an ongoing excursion, every
  other call (no home set, no excursions, every excursion already
  closed) is unaffected.
- If a device goes offline mid-walk for an unrelated reason (dead
  battery, lost signal somewhere away from home) rather than because the
  pet is back, this will still close the excursion at that offline time,
  there's no way to distinguish "went quiet because it's home" from
  "went quiet because something's wrong" from Traccar's device status
  alone. Judged an acceptable trade: an excursion stuck open forever is
  a worse, guaranteed failure mode than an occasional early close on a
  genuinely interrupted walk.
