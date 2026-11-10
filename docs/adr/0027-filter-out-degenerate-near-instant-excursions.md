# 27. Filter out degenerate, near-instant excursions

## Status

Accepted.

## Context

A real-world report: one of Phoebe's excursions showed up in the app as
a "0 min" walk with no route at all. The underlying Traccar events
didn't show an obvious cause, every other exit/enter pair for the same
device in the same window was 26 minutes to over an hour apart, nothing
looked literally simultaneous at the raw event level.

Regardless of the exact trigger (GPS jitter right at the geofence
boundary is the likeliest guess, a position bouncing just outside, then
back inside, in quick succession), the result is a pairing where
`enter.eventTime` resolves to at or barely after `exit.eventTime`. The
bounded position-history fetch between them (see `makeExcursion`) then
has at most one fix to work with, nowhere near enough to compute a real
route or distance, and the excursion still gets built and shown as if
it were a genuine (if extremely short and uneventful) trip.

## Decision

`TraccarPetRepository.isDegenerate(_:)`, a small pure function: an
excursion whose `duration` (always `nil`-safe, a still-open excursion is
never degenerate) is less than `minimumExcursionDuration` (60 seconds)
is degenerate and filtered out entirely, not shown, not counted toward
lifetime stats, not persisted into the excursion cache.

60 seconds, not some smaller/larger number: a real Mictrack reports
every 30 seconds unconditionally (confirmed by the device owner, see
ADR-0025), so a gap shorter than twice that can't reflect any real
movement in between no matter what caused the exit/enter pair to be
this close together.

Applied in two places in `fetchExcursions`, not just one:

- On `freshExcursions`, before they're merged into the persisted cache,
  so a degenerate excursion is never written there in the first place.
- Again on the final merged `all`, right before returning, so an
  already-cached degenerate excursion (like Phoebe's, cached before this
  check existed) is hidden immediately too, without requiring a manual
  "Recalculate Lifetime Stats" (see ADR-0026) to flush it first. The
  underlying cache entry itself isn't touched or removed by this, it's
  simply never surfaced.

## Consequences

- A pet whose tracker sits exactly on a geofence boundary, triggering
  this repeatedly, will see those specific moments silently dropped from
  their excursion history rather than cluttering it with meaningless
  "0 min" entries. Nothing currently surfaces how often this filter
  actually fires, if that turns out to matter it's a straightforward
  follow-up.
- Distance/duration are unaffected either way: a degenerate excursion's
  own contribution to lifetime totals was already ~0 before this filter,
  this only changes whether it's rendered as a confusing, empty-looking
  list entry.
