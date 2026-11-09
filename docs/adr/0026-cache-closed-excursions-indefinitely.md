# 26. Cache closed excursions indefinitely, never invalidated by a later home change

## Status

Accepted.

## Context

`fetchExcursions(forPetID:from:to:)` recomputed every excursion in the
requested window from scratch on every call: fetch the home-geofence
exit/enter events in range, pair them, then for each pair fetch its own
position history and run `firstHomecomingPause` over it (ADR-0025). None
of that depends on anything that changes once an excursion has actually
closed (`endTime != nil`), the underlying Traccar events and positions are
historical fact, but it was all redone anyway, every time `ExcursionsView`
or `TrailView` loaded, for excursions that could be months or years old
and long since settled.

Not a problem observed in practice yet (a handful of excursions per day,
`fetchExcursions`' own `maxConcurrent: 20` bound already keeps a single
load reasonable), raised instead as a "what does this look like after a
year of history" question. The honest answer was "a lot of repeated,
pointless network/compute work," so this gets ahead of it now rather than
waiting for it to actually hurt.

### The real design question: what happens when a home changes later

The first instinct was to treat this the way `lifetimeExcursionStats`
already caches *totals* (ADR-0014's "Lifetime stats" section): cache,
but invalidate if anything the computation depends on changes, here, the
pet's configured homes, since `firstHomecomingPause` matches a position
against whichever homes are currently configured.

Revisited: that instinct was backwards. An excursion that happened last
year happened against whatever home existed last year, at wherever it was
then, whatever radius it had then. If the owner later moves "Home" across
town, or deletes it and sets up a new one, that shouldn't reach back and
change what a `firstHomecomingPause`-closed excursion "a year ago"
looks like. Keeping it exactly as first computed isn't a staleness bug to
work around, it's the only interpretation that treats an excursion as a
historical record rather than a live view of the present home
configuration. This only matters for excursions `firstHomecomingPause`
ever actually closes (see ADR-0025), one with a real `geofenceEnter`
event that `shouldPreferHomecoming` never overrides needs no homes data
at all to compute its `endTime`/distance, those were already fully
home-independent.

### Revision: a narrow first query can poison the cache for every wider one after it

Confirmed live, same day this shipped: a real pet's Excursions screen
started showing only today's excursions, everything older had silently
disappeared. Root cause was a gap the original version of this decision
never accounted for: `PetDetailViewModel.loadTodaysExcursions()` queries
`fetchExcursions(from: startOfDay, to: .now)`, a narrow, recent range,
and `PetDetailView` fires it (among other `.task`s) on every load. If
that happens to be the *first* call that ever populates a pet's
excursions cache, `cachedThroughEndTime` ends up set from only that
narrow range, e.g. "today," even though the cache has never actually
seen anything before today. The original `fetchExcursions` trusted that
watermark unconditionally: a later, wider call (`ExcursionsView`'s own
7-day window) saw a non-nil `cachedThroughEndTime` and narrowed its live
fetch to `max(from, watermark)`, silently treating "today" as "already
fully cached back to the beginning of time," meaning every excursion
genuinely older than today never got fetched, cached, or shown again.

Fixed by tracking the cache's own contiguous coverage separately from
the watermark: `CachedExcursions.coveredFrom`, the earliest point this
cache is actually known-complete from. `TraccarPetRepository.liveFetchStart(cached:from:)`
(pulled out, unit tested directly) only narrows to the watermark when
`coveredFrom <= from`, otherwise it fetches the entire requested range
live, regardless of what the watermark claims, closing the gap and
extending `coveredFrom` back to it. Self-healing for anyone who already
hit this: an old cached blob has no `coveredFrom` key at all, decodes to
`nil` (missing key on an `Optional` property), which `liveFetchStart`
treats the same as no cache at all, the very next call ignores the
poisoned watermark and rebuilds correctly, no manual cache reset needed.

## Decision

- `CachedExcursions` (new, `LibrePawKit/Repositories/ExcursionCacheStore.swift`):
  `{ excursions: [Excursion], coveredFrom: Date?, cachedThroughEndTime: Date? }`.
  `cachedThroughEndTime` is the same watermark shape as
  `CachedLifetimeStats`; `coveredFrom` is this cache's own addition (see
  Revision above), the earliest point coverage is contiguous from. Only
  *closed* excursions (`endTime != nil`) ever go into `excursions`, an
  ongoing one is never persisted, its distance/end are still growing.
- `ExcursionCacheStore` protocol + `UserDefaultsExcursionCacheStore`,
  keyed `org.librepaw.excursionsCache.<serverHost>.<petID>`, the same
  per-pet-per-server keying `UserDefaultsLifetimeStatsStore` already uses
  and for the same reason (device ids are only unique within one server).
- `fetchExcursions(forPetID:from:to:)`: loads the cache first, calls
  `TraccarPetRepository.liveFetchStart(cached:from:)` to decide where to
  start the live fetch from (`from` itself unless `coveredFrom` already
  reaches back to or before it, see Revision above), fetches
  events/positions only for `[liveFrom, to]`. The result merges cached
  and freshly-computed excursions (deduplicated by id, an excursion's own
  exit event id, stable and unique within a server) and re-filters to the
  originally requested window before returning, since the cache itself
  holds everything ever seen, not just this call's range.
- `TraccarPetRepository.mergeExcursions(cached:freshExcursions:liveFrom:)`
  and `liveFetchStart(cached:from:)`, both pure static functions pulled
  out for direct unit testing, the same pattern as
  `mergeLifetimeStats`/`pairHomeExitsWithEnters`/`firstHomecomingPause`.
- `PetRepository.resetExcursionsCache(forPetID:)` discards a pet's cached
  excursions entirely, the recovery path for a bad cached one (e.g. one a
  since-fixed bug closed wrong), the same reasoning as
  `resetLifetimeStats(forPetID:)`. The existing "Recalculate Lifetime
  Stats" context-menu action (added for exactly that reasoning, no ADR of
  its own) now clears both caches together, `PetDetailViewModel`'s method
  renamed `resetLifetimeStats()` → `recalculate()` to match: excursions
  cache first, then lifetime stats (which is itself built from
  `fetchExcursions`, clearing it first would just re-read the still-bad
  cached excursions right back into a freshly-cleared total).
- `Excursion` and `Coordinate` both gained `Codable`, needed to persist
  `CachedExcursions` as JSON the same way `CachedLifetimeStats` already
  is.

## Consequences

- Reopening Excursions/Trail for a window that's entirely in the past
  (already fully cached) costs no network requests at all beyond the
  homes/events check needed to confirm nothing new closed since the
  watermark, a meaningful win once there's enough history for this to
  matter, which was the entire point.
- Unbounded local growth: every closed excursion a pet has ever had stays
  in `UserDefaults` forever, there's no cap or eviction. For an ordinary
  dog going on a few walks a day this is a few thousand small entries
  after several years, not expected to be a real problem, but genuinely
  untested at that scale. Revisit with a size cap, or a dedicated on-disk
  store instead of `UserDefaults`, if it turns out to matter in practice.
- A real, accepted trade-off given the Decision above: editing or
  deleting a home does not retroactively change how any already-closed
  excursion reads, even one that technically "shouldn't" have closed the
  way it did under today's home configuration. This is intentional, not
  a bug, see Context.
- Same caveat ADR-0023/0014 already note elsewhere: this is purely a
  client-side, per-device cache. Reinstalling the app, or using a second
  device/simulator, starts cold and rebuilds it from scratch, which is
  correct and expected, not a cache "going stale."
