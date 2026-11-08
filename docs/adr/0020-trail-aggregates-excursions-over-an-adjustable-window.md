# 20. "Trail" aggregates excursions over an adjustable window, replacing "Today's Trail"

## Status

Accepted.

## Context

`TodaysTrailView` drew one raw position-history fetch (midnight to now) as a
single polyline. Two problems with that, once excursions existed as their
own first-class concept (ADR-0014):

- It duplicated what `ExcursionsView` already computes, a walk is already
  the meaningful unit, not an arbitrary calendar-day boundary. A walk
  starting at 11pm and ending after midnight got silently split across two
  "today" views.
- There was no way to look further back than the current day, or to tell
  one walk apart from another on the map, the whole day rendered as a
  single undifferentiated line.

## Decision

- Renamed to **Trail** (`TrailView`/`TrailViewModel`, replacing
  `TodaysTrailView`), reached from `PetDetailView`'s "Trail" row exactly
  where "Today's Trail" used to be.
- Default window is 24 hours, adjustable via a segmented control
  (`TrailWindow`: 24 Hours, 3 Days, 7 Days, 30 Days) that reloads on change.
- Built from the same `fetchExcursions(forPetID:from:to:)` the Excursions
  list uses, not a single raw trail fetch, each excursion in the window
  gets its own `fetchTrail` call (concurrent, one per excursion) and its
  own `MapPolyline`, colored from a fixed 10-color palette cycled by the
  excursion's position in the (most-recent-first) list, stable across
  reloads of the same window.
- Tapping a route opens that excursion's own `ExcursionDetailView`, the
  same destination `ExcursionsView`'s rows push to. First attempt was
  `Map`'s native `selection:` binding with `.tag(excursion.id)` on each
  `MapPolyline`, that compiles but doesn't actually work, confirmed live
  (multiple taps directly on a clearly visible route, in the simulator,
  never fired a selection change). `MapPolyline` isn't a tappable target
  in this API at all. Landed on the same pattern `PetMapView` already uses
  for pet pins instead: a small `NavigationLink`-wrapped `Annotation`
  marker, colored to match its route and dropped at the route's midpoint
  fix, which is a proven-reliable tap target since it's a real SwiftUI
  view, not a map overlay shape.
- `PetDetailViewModel.loadTodaysTrail()`/`trail`/`totalTrailDistanceMeters`
  are unchanged and still literally mean "today", they back the pet
  detail page's own "Distance Today" stat tile, a separate concern from
  this screen.

## Consequences

- One `fetchTrail` call per excursion in the window (concurrent, unbounded)
  rather than one fetch for the whole range, worth revisiting with a
  concurrency cap (same reasoning as `fetchExcursions`' own, see the
  "Bound fetchExcursions' concurrent position-history fetches to 20 at
  once" commit) if a pet's excursion count in a 30-day window ever gets
  large enough for it to matter in practice.
- Worth revisiting if MapKit ever adds real polyline hit-testing: the
  marker approach means tapping has to land on a small dot rather than
  anywhere along the line, a real but second-order usability cost next to
  having a reliable tap target at all.
