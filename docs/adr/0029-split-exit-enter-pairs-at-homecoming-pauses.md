# 29. Split one exit/enter pair into several excursions at homecoming pauses

## Status

Accepted, amends [ADR-0025](0025-close-excursions-when-the-device-goes-offline.md)
and [ADR-0026](0026-cache-closed-excursions-indefinitely.md).

## Context

A real-world report on 2026-11-13: during an afternoon walk with Phoebe,
no new excursion appeared. Recalculating brought back the morning's
excursion as if it were still ongoing, and once Phoebe was home again
the afternoon walk was gone entirely.

Traccar's own events for that day were exactly one `geofenceExit` (08:39)
and one `geofenceEnter` (16:12). The position trail showed two separate
walks:

- 08:39 to 09:17, after which the tracker fell asleep 42m from the
  center of a 40m home, 2m short of the boundary, so no enter event
  (the ADR-0025 case).
- 15:12 to 16:12, the tracker having woken up 126m away, already outside
  the fence, so no exit event either, Traccar still considered the pet
  outside since 08:39.

ADR-0025 had already named this as "a real gap ... not something
fixable client-side": its homecoming pause closed the first walk, but
the second walk, never getting an exit event of its own, had no
excursion. In practice it was worse than a missing second walk, three
separate mechanisms each mishandled the pair:

1. While the pair was open, the morning walk was closed at the pause
   and cached as final (ADR-0026), moving the cache watermark past the
   08:39 exit. Every later fetch started after it, found no new exit,
   and so never looked at the afternoon at all.
2. Recalculating cleared the cache and re-evaluated the open pair from
   08:39, but `requireStaysHomeAfterward` (added so a brief signal gap
   right after leaving couldn't close a walk early) now saw the pet far
   from home again in the afternoon and rejected the morning pause, so
   the whole pair read as one walk ongoing since 08:39.
3. Once the enter event arrived, the closed pair ended at the morning
   pause and its trail was cut there, dropping the afternoon.

Looking through the previous 30 days turned up a second shape of the
same problem: an exit at 14:17 on 11-10 that was GPS jitter at 48m from
a 40m home, the tracker asleep there overnight (with a brief report at
86 to 123m in the evening), and the real walk only at 12:59 the next
day. That pair read as one 23-hour excursion.

## Decision

An exit/enter pair is no longer one excursion by definition. The
position trail decides how many it stands for:
`TraccarPetRepository.splitIntoExcursions(exit:enter:trail:homes:trailEndTime:)`,
a pure, unit-tested function, walks the trail segment by segment.

- A segment ends at its first homecoming pause (ADR-0025, unchanged:
  within 100m beyond a home's radius, then at least five minutes of
  silence), as long as that's earlier than a real enter event, otherwise
  at the enter event, or not at all while the pair is still open.
- After a pause, the next segment starts where the trail next goes
  clearly away from every home (beyond radius plus the 100m slack, so
  pottering about just outside the fence doesn't count), backdated over
  the moving positions right before it that are already outside the
  home's own radius, stopping at a quiet gap (that's the tracker asleep,
  not the walk starting). No such position, no further segment.
- A segment that never got clearly away before its pause, but is
  followed by a departure, is dropped as a stub: the jitter exit above,
  or a few minutes without signal by the front door. The walk after it
  keeps the exit's id but starts at its real departure. This replaces
  `requireStaysHomeAfterward`, which handled the front door case by
  refusing any pause the pet later walked away from, and so also refused
  genuine homecomings like the one above.
- The first segment keeps the exit event's id. A later one has no event
  of its own and is identified by its first position's id, negated so it
  never collides with an event id. Both are stable across recomputation,
  history only gets appended to.

Caching (ADR-0026) changes accordingly:

- Every excursion split out of a pair Traccar hasn't closed yet is
  provisional, shown but neither cached nor advancing the watermark,
  even one that already ended at a pause, since later positions can
  still turn the rest of the pair into further walks.
- A live fetch starts at the cache's watermark even when the request's
  own `from` is later: whatever follows the watermark isn't final yet,
  and the exit that opened it can lie before `from`.
- Lifetime stats evaluate the whole (mostly cached) history rather than
  only from their own watermark, which can fall in the middle of a
  still-open pair. `mergeLifetimeStats` already skips what was counted.
- Both cache keys moved to v3, caches written before this can hold a
  walk closed at a pause as final with the watermark past its open exit.

## Consequences

- Verified against the live server: Phoebe's 2026-11-13 now shows both
  walks (08:39 to 09:17 and 15:12 to 16:12, each with only its own
  distance), and 11-10/11's 23-hour excursion is the 31-minute walk on
  11-11 it really was. The remaining 15 excursions of the last 30 days
  are unchanged.
- A second walk's start is the first position the tracker reported after
  waking up, not the moment the pet really left, which happened at some
  unknown point while it was asleep. Nothing better is knowable.
- A stub's walk starts at its departure, so the few minutes of a front
  door dead spot are no longer counted. Judged far better than the
  alternative it replaces, losing or merging whole walks.
- A gap of five minutes or more in reports near home is still read as
  the tracker asleep. The Mictrack reports every 30 seconds while awake
  (ADR-0025), so this needs a genuinely dropped connection, not just a
  pause in movement.
- Not addressed here: exits and enters with identical timestamps (only
  seen in injected test data so far) can still pair into overlapping
  excursions, a pairing question rather than a splitting one.
