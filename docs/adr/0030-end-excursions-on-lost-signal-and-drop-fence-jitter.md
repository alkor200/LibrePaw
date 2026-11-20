# 30. End an excursion when the tracker goes silent away from home, drop fence jitter

## Status

Accepted, amends [ADR-0029](0029-split-exit-enter-pairs-at-homecoming-pauses.md)
and [ADR-0027](0027-filter-out-degenerate-near-instant-excursions.md).

## Context

A real-world report on 2026-11-20 about Phoebe's 2026-11-15/16: one
excursion lasting 23 hours, followed by one lasting a single minute.
Every other excursion of the past 30 days was correct.

The trail showed two problems ADR-0029's splitting didn't cover:

- **The battery died a few minutes into a walk.** Exit at 21:06, the
  last fix at 21:13 about 330m from home, then nothing until the
  tracker was switched on again the next evening at 20:19, already
  about 150m away on the next walk, which ended with a real enter event
  at 20:50. ADR-0029 splits a pair at a homecoming pause, a silence
  *near* home. This silence started far away, so the whole pair, both
  walks and the night in between, read as one 23-hour excursion.
- **Fence jitter.** An exit at 50m from a 40m home and an enter at 33m
  exactly one minute later. ADR-0027 filters excursions strictly
  shorter than 60 seconds, so this one got through as a one-minute walk.

## Decision

`TraccarPetRepository.splitIntoExcursions` gains two rules:

- **Lost signal.** A segment also ends at its last fix before a silence
  of at least `lostSignalGap` (2 hours) that starts away from home
  (beyond the home's radius plus the 100m slack). Away from home the
  Mictrack never sleeps on its own (ADR-0025), so a silence that long
  means an empty battery or no network. The excursion is marked
  `endedWithLostSignal` and gets no end home. Once the tracker reports
  again, a new segment starts as soon as the trail is clearly away from
  home, the same departure rule ADR-0029 uses after a homecoming pause,
  since the pet can't have been out all that time. While a pair is
  still open, the silence is measured against now, so a walk whose
  battery died is closed once two hours have passed, provisionally,
  like everything else from an open pair.
- **Fence jitter.** A closed segment shorter than
  `maximumJitterDuration` (5 minutes) that never got clearly away from
  home is dropped. Measured on the trail rather than only the duration,
  so a short but real outing near home that lasts longer is kept.

The app shows "Signal lost" on such an excursion in the list and
explains in its detail screen that the walk probably went on longer
than the tracker could see.

Both cache keys move to v4: caches written before this hold the
23-hour excursion as final and have folded it into the lifetime totals.

## Consequences

- Verified against the live server: 2026-11-15's evening walk is now
  21:06 to 21:13 marked as signal lost, 2026-11-16's evening walk is its
  own 30-minute excursion, the one-minute jitter is gone, and the other
  37 excursions of the past 30 days are unchanged.
- An excursion that lost its signal understates distance and duration,
  nothing after the last fix is knowable. It still counts toward the
  lifetime totals with what is known.
- A dead spot away from home longer than two hours would cut a walk in
  two. Judged far less likely than a dying battery, and the two halves
  are still both shown.
- `Excursion` gained `endedWithLostSignal`, cached alongside the rest.
