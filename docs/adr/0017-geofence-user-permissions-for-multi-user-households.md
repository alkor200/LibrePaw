# 17. Grant explicit user permissions when creating or editing a home geofence

## Status

Accepted — amends [ADR-0016](0016-multiple-home-geofences-per-pet.md).
The "a non-admin can still create/edit a home, just only visible to
themselves" behavior described below was superseded by
[ADR-0018](0018-admin-only-homes-and-pet-sharing.md), which hides home
management from non-admins entirely rather than let them use a feature
that only partially works. The permission findings themselves (what
Traccar's API actually does) still stand.

## Context

After shipping multiple homes per pet (ADR-0016), two bugs surfaced in real
use against a live server with more than one Traccar account:

- Different user accounts saw **different** home geofences for the same
  pet.
- Reloading `HomesView` sometimes showed "Couldn't Load Homes" with a
  cancellation-flavored message, even though the list had just loaded fine.

The first turned out to be a real gap in ADR-0014/ADR-0016: Scentrail only
ever linked a new geofence to the pet's **device** (`POST /api/permissions
{deviceId, geofenceId}`), never to a **user**. Tested directly against a
live server (not guessed from docs) with a dedicated non-admin test
account:

- `GET /api/geofences?deviceId=X` **is** filtered per-user — a device link
  alone does not make a geofence visible to every user who can see that
  device. Each user additionally needs their own `{userId, geofenceId}`
  permission. (Traccar's own docs/forum say the same thing; this confirms
  it against this server's actual behavior rather than trusting the docs
  alone.)
- An initial fix attempt tried to discover "who am I" via `GET /api/users`
  (no query params) and "who else can see this device" via `GET
  /api/permissions?deviceId=X&userId=0`. Both were wrong, confirmed live:
  - `GET /api/users`, for a non-admin account, returns `[]` — **always**,
    even `?userId=<the account's own id>`. It does not return "yourself."
    The `userId` query parameter is explicitly admin/manager-only per
    Traccar's own API reference; the bare call being just-as-useless for a
    non-admin wasn't obvious from the docs and only showed up by calling it.
  - `GET /api/permissions` — for **any** query shape, including one that
    only asks about the caller's own permissions — throws
    `java.lang.SecurityException: Administrator access required` (HTTP
    `400`, with a raw Java stack trace as the body, not a JSON error).
    `PermissionsService.checkAdmin()` runs unconditionally before the
    query parameters are even inspected.
  - `POST /api/permissions` for a link that **already exists** was tested
    twice in a row and both times returned `204` — it's idempotent, not an
    error. This matters: an earlier draft of this fix diffed against
    existing links first (via the now-known-broken `GET /api/permissions`
    call) specifically to avoid a feared duplicate-link error that, tested
    directly, doesn't actually happen.
  - `GET /api/session` with Basic Auth returns `404` (confirms ADR-0012's
    "ignores Basic Auth entirely" still holds); with the cookie from `POST
    /api/session` it returns the full `User` object, `id` included, for a
    non-admin account too. This *is* a reliable way to learn "who am I."

The second bug (spurious "cancelled" on reload) was unrelated to the
Traccar API: `HomesView` reloads from `.onAppear`, which fires every time
the view is revisited (after editing a home, for instance) — unlike
`.task`, nothing cancels a stale in-flight load before a newer one starts,
so two overlapping `homeGeofences` fetches could race, and the loser's
`CancellationError`/cancelled-transport error was displayed as if it were
a real failure.

## Decision

- `TraccarClient.fetchCurrentUser()` now resolves the current user via the
  ADR-0012 cookie-session dance (`POST /api/session` to establish the
  cookie, `GET /api/session` for the `User` object) instead of `GET
  /api/users`.
- `TraccarPetRepository.syncGeofenceVisibility(geofenceId:petID:)` (called
  from both `addHomeGeofence` and `updateHomeGeofence`) does two
  unconditional, best-effort grants, neither diffed against existing links
  first (confirmed safe — see above):
  1. `fetchCurrentUser()` then `linkGeofence(toUserId:)` — works for any
     account, admin or not. This is the one every user gets.
  2. `fetchPermittedUserIDs(deviceId:)` (`GET
     /api/permissions?deviceId=X&userId=0`) then `linkGeofence(toUserId:)`
     for each — **only** succeeds for an administrator account; for
     anyone else it fails immediately and is silently skipped.
- Practical consequence worth knowing: a non-admin household member who
  creates or edits a home makes it visible to themselves, but **not**
  automatically to other non-admin accounts sharing the same pet — Traccar
  gives no API, at any permission level, for a non-admin to even discover
  who else can see a device, let alone grant them anything. An
  administrator account editing that same home once (even without
  changing anything) runs the second step successfully and extends it to
  everyone with device access. There is no in-app indication of which case
  applies; it depends entirely on whether the signed-in account is a
  Traccar admin.
- **This is worse than "can't see the home pin."** Tested directly with two
  separate non-admin accounts sharing device-level access to the same pet,
  on a freshly created geofence with real crossing events (a device sending
  live TLT-2H position reports — see `docs/adr` note below on how this was
  verified): the account with no explicit geofence permission got `[]` from
  `GET /api/reports/events?type=geofenceExit` / `geofenceEnter` — not a
  permission error, an empty, successful response — for events that
  genuinely existed and were visible to the other account on the same
  query. Since `fetchExcursions` filters events by querying
  `GET /api/geofences?deviceId=` first (see ADR-0014, ADR-0016) and that
  call is subject to the exact same per-user filtering, a user without
  geofence permission doesn't just lose the ability to view/edit the home —
  **their excursions list for that pet is silently empty**, indistinguishable
  from "no excursions happened" or "no home set." There's no error to catch
  or surface; the data just isn't there for that account.
- Confirmed this is deliberate Traccar design, not a gap: the official docs
  describe sharing a geofence as an explicit admin action ("As an admin you
  can share any objects including geofences from Settings > Users menu"),
  and no server config setting changes this. A household fully composed of
  non-admin accounts has no way — through the app, through any API call, or
  through any documented server setting — to get working shared excursions
  without at least one admin account in the mix.
- `HomesViewModel.load()` now cancels any load already in flight before
  starting a new one, and treats a cancelled load as "superseded," not a
  failure — it no longer sets `errorMessage` when `Task.isCancelled`.

## Consequences

- No more "diff existing permissions first" complexity: `POST
  /api/permissions` being idempotent means both grant steps can run
  unconditionally on every add *and* every edit, which also makes editing
  a home (even a no-op save) the repair path for one that predates this
  fix or whose sync partially failed.
- The admin-only ceiling on discovering/granting other users' access is a
  real Traccar limitation, not a Scentrail shortcut — there is currently no
  way to fully close it from a non-admin account. Worth revisiting only if
  Traccar adds a less-privileged "who else can see this device" endpoint.
- This ADR's own first draft is itself an example of the exact mistake
  ADR-0012's "Consequences" warned about — Traccar behavior (`GET
  /api/users` returning "self") assumed rather than checked against a live
  server. Caught quickly this time only because multi-account testing
  surfaced it immediately; the fix was to go back and call the real
  endpoints directly rather than keep guessing from docs/forum posts.
