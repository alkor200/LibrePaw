# 25. Close an excursion once the trail pauses back near home

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

### Two approaches tried and ruled out first

**The device's live online/offline status.** The first version of this
fix checked, for the one still-open excursion, whether the device had
since gone offline, and if so treated its last known update time as the
end. This worked for the reported case, but has a real flaw: the
device's status is a live value, re-read fresh on every call. If the
device comes back online later, e.g. a second walk starts before
Traccar ever logs a real enter event for the first one, the closing
condition no longer holds, and the next `fetchExcursions` call would
show the *original* excursion as "ongoing" again, silently merging the
first walk, the time at home, and the start of the second walk into one
excursion.

**A `deviceOffline` event.** Traccar does have a `deviceOffline`/
`deviceOnline` event pair in its notification catalog, which, unlike
live status, would be a permanent historical record immune to the
reopening problem above. Tested directly against this project's own
Traccar server: confirmed `deviceOffline` is only ever logged when a
device's network *connection* is explicitly closed, which several
common tracker protocols (including, evidently, both devices used for
testing this project) never do, they just stop sending without closing
anything a server can detect that way. Confirmed live: zero
`deviceOffline` events in 30 days for either test device, despite both
genuinely having gone offline, while `deviceMoving`/`deviceStopped`
(unrelated event types) logged normally in the same window, ruling out
a broader "events aren't being recorded at all" explanation. This isn't
a configuration problem to fix, it's inherent to how several tracker
protocols report, including (most relevantly) exactly the kind of
battery-conscious device this whole feature exists for.

### Revision: a real enter event can itself arrive hours late

Confirmed against a real walk: the device went quiet in standby a short
distance outside the home geofence, same situation as above, except this
time a real `geofenceEnter` event eventually did arrive, about four hours
later, once the device woke back up and actually crossed the boundary.
The original version of this fix only ran `firstHomecomingPause` for the
still-open case (`enter == nil`), so a real, if very late, enter event
always won outright, and the excursion was recorded as roughly four hours
long rather than ending at the near-home pause shortly after it actually
started.

Fixed by running `firstHomecomingPause` unconditionally, whether or not a
real enter event exists, and preferring whichever end is earlier. This
needs no extra guard against overriding a *good* enter event with a worse
one: `firstHomecomingPause` only ever searches the trail already bounded
by `[exit, fetchedEndTime]`, so any pause it finds is always at or before
the real enter event's own time, never after it. For an ordinary quick
return, the only "pause" in that bounded window ends up being the enter
position itself (nothing to find a gap against beyond it), so the result
doesn't change. For the four-hour case, the near-home position before the
quiet gap is now found and wins.

Also lowered `quietGapAfterHomeProximity` from 20 to 5 minutes: confirmed
live that a real Mictrack reports every one to two minutes while moving,
so a 5-minute gap is already a reliable signal that the device stopped
reporting, and 20 minutes was needlessly slow to close an excursion that
clearly already ended.

## Decision

Close the excursion using only data already fetched for it: the home
geofence's own geometry, and the position trail `makeExcursion` already
retrieves to compute distance. No device status, no new event type, no
locally persisted state.

- `TraccarPetRepository.firstHomecomingPause(in:homes:proximitySlackMeters:minimumQuietGap:)`,
  a pure, static, unit-tested function (ten cases: closes on a near-home
  position followed by silence, honors the proximity slack beyond a
  home's own radius, ignores positions genuinely far from any home,
  doesn't trigger on a brief pass near home followed by continued
  movement, picks the earliest qualifying pause, matches against
  whichever configured home is nearest, the 5-minute threshold boundary
  both just under and at/over, and handles an empty trail or no homes at
  all). Walks a device's position trail chronologically and returns the
  first position that both:
  - falls within `homeProximitySlackMeters` (100m) of a home, beyond its
    own configured radius, and
  - is followed by at least `quietGapAfterHomeProximity` (5 minutes) of
    silence, or is simply the last position in the trail.
- `makeExcursion` calls this unconditionally, whether or not a real enter
  event already exists (see "Revision" above), against the trail it
  already fetched; if a homecoming pause is found, that position's time
  and home become the excursion's `endTime`/`endHomeID`, the same outcome
  as a real enter event, and the distance/end-coordinate are recomputed
  over just the trail up to that point rather than whatever the device
  reported afterward (e.g. a second walk, or the same device waking back
  up hours later).
- `fetchExcursions` now also maps the home geofences it already fetches
  into `[HomeGeofence]` and passes them through to `makeExcursion`.

The 100m slack and 5-minute quiet threshold are both flat constants
(`TraccarPetRepository.homeProximitySlackMeters`/
`quietGapAfterHomeProximity`): a flat margin rather than a multiple of
the home's own radius, since homes are deliberately small (20-100m, see
`SetHomeView`'s slider), generous enough to cover "a few meters short of
the boundary" plus ordinary GPS jitter, without reaching into unrelated
nearby places.

### Why this doesn't reopen

Unlike live device status, a quiet gap that has already happened in the
historical trail is a fixed fact. Re-running `fetchExcursions` later,
even with a second walk's positions now appended after that gap, finds
the exact same near-home position followed by the exact same gap in the
exact same place, and reaches the same answer every time. No local
state has to remember the decision between calls, the trail itself is
the record.

## Consequences

- **Correction:** this originally claimed there was no way to inject a
  GPS position from here, that was wrong, not just outdated. A simulated
  device already sent real TLT-2H position reports to inject geofence
  events for ADR-0017/ADR-0018's own testing, before this ADR was
  written, so the capability already existed and was simply
  overlooked when writing this one down. The device-ingestion ports
  (confirmed open: port 5030, TLT-2H/Mictrack) are separate from the
  REST API (which is indeed read-only for positions/events) and need no
  credentials; the working script lives outside this repository (see the
  gitignored local agent notes), not committed here since it embeds test
  server specifics. Original text, kept for history: verified instead by
  the eight unit tests covering the decision logic directly (including
  the specific "near home, then quiet" vs. "near home, still moving"
  distinction the live scenario depends on), and a live regression pass
  confirming `fetchExcursions` still behaves correctly (no crash, same
  empty-state result as before) for both test pets. A live end-to-end
  reproduction of the four-hour-late-enter-event case from the Revision
  above is possible with that script and worth doing as a follow-up,
  not yet done as of this revision.
- A real gap remains, inherent to the underlying event model, not
  something fixable client-side: if the pet leaves again before the
  device ever reports a position genuinely inside a home geofence (not
  just within the slack), Traccar's own exit/enter state never properly
  resets, so that second walk won't appear as its own distinct
  excursion, it'll simply never generate a new exit event to pair
  against. This fix only prevents the *first* walk's entry from reading
  "Away now" forever once it's actually over, it doesn't give the
  second walk a tracked excursion of its own.
- If the device's trail happens to show it lingering near a home for
  other reasons (a long stop just outside the fence that isn't actually
  the pet coming inside, e.g. tied up on the porch), this will still
  close the excursion there. Judged an acceptable trade: an excursion
  stuck open forever is a worse, guaranteed failure mode than an
  occasional early close on a stop that merely looks like coming home.
