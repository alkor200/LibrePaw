# 17. Grant explicit user permissions when creating or editing a home geofence

## Status

Accepted, amends [ADR-0016](0016-multiple-home-geofences-per-pet.md).
The "a non-admin can still create/edit a home, just only visible to
themselves" behavior described below was briefly superseded by
[ADR-0018](0018-admin-only-homes-and-pet-sharing.md) (hide home management
from non-admins entirely) and then restored by
[ADR-0019](0019-reenable-non-admin-homes-with-a-visibility-notice.md),
which shows the screen to everyone again with the limitation stated
in-app instead of hidden, this ADR's original behavior is back in effect.
The permission findings themselves (what Traccar's API actually does)
still stand throughout.

## Context

After shipping multiple homes per pet (ADR-0016), two bugs surfaced in real
use against a live server with more than one Traccar account:

- Different user accounts saw **different** home geofences for the same
  pet.
- Reloading `HomesView` sometimes showed "Couldn't Load Homes" with a
  cancellation-flavored message, even though the list had just loaded fine.

The first turned out to be a real gap in ADR-0014/ADR-0016: LibrePaw only
ever linked a new geofence to the pet's **device** (`POST /api/permissions
{deviceId, geofenceId}`), never to a **user**. Tested directly against a
live server (not guessed from docs) with a dedicated non-admin test
account:

- `GET /api/geofences?deviceId=X` **is** filtered per-user, a device link
  alone does not make a geofence visible to every user who can see that
  device. Each user additionally needs their own `{userId, geofenceId}`
  permission. (Traccar's own docs/forum say the same thing; this confirms
  it against this server's actual behavior rather than trusting the docs
  alone.)
- An initial fix attempt tried to discover "who am I" via `GET /api/users`
  (no query params) and "who else can see this device" via `GET
  /api/permissions?deviceId=X&userId=0`. Both were wrong, confirmed live:
  - `GET /api/users`, for a non-admin account, returns `[]`, **always**,
    even `?userId=<the account's own id>`. It does not return "yourself."
    The `userId` query parameter is explicitly admin/manager-only per
    Traccar's own API reference; the bare call being just-as-useless for a
    non-admin wasn't obvious from the docs and only showed up by calling it.
  - `GET /api/permissions`, for **any** query shape, including one that
    only asks about the caller's own permissions, throws
    `java.lang.SecurityException: Administrator access required` (HTTP
    `400`, with a raw Java stack trace as the body, not a JSON error).
    `PermissionsService.checkAdmin()` runs unconditionally before the
    query parameters are even inspected.
  - `POST /api/permissions` for a link that **already exists** was tested
    twice in a row and both times returned `204`, it's idempotent, not an
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
the view is revisited (after editing a home, for instance), unlike
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
  first (confirmed safe, see above):
  1. `fetchCurrentUser()` then `linkGeofence(toUserId:)`, works for any
     account, admin or not. This is the one every user gets.
  2. `fetchPermittedUserIDs(deviceId:)` (`GET
     /api/permissions?deviceId=X&userId=0`) then `linkGeofence(toUserId:)`
     for each, **only** succeeds for an administrator account; for
     anyone else it fails immediately and is silently skipped.
- Practical consequence worth knowing: a non-admin household member who
  creates or edits a home makes it visible to themselves, but **not**
  automatically to other non-admin accounts sharing the same pet, Traccar
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
  live TLT-2H position reports, see `docs/adr` note below on how this was
  verified): the account with no explicit geofence permission got `[]` from
  `GET /api/reports/events?type=geofenceExit` / `geofenceEnter`, not a
  permission error, an empty, successful response, for events that
  genuinely existed and were visible to the other account on the same
  query. Since `fetchExcursions` filters events by querying
  `GET /api/geofences?deviceId=` first (see ADR-0014, ADR-0016) and that
  call is subject to the exact same per-user filtering, a user without
  geofence permission doesn't just lose the ability to view/edit the home -
  **their excursions list for that pet is silently empty**, indistinguishable
  from "no excursions happened" or "no home set." There's no error to catch
  or surface; the data just isn't there for that account.
- Confirmed this is deliberate Traccar design, not a gap: the official docs
  describe sharing a geofence as an explicit admin action ("As an admin you
  can share any objects including geofences from Settings > Users menu"),
  and no server config setting changes this. A household fully composed of
  non-admin accounts has no way, through the app, through any API call, or
  through any documented server setting, to get working shared excursions
  without at least one admin account in the mix.
- `HomesViewModel.load()` now cancels any load already in flight before
  starting a new one, and treats a cancelled load as "superseded," not a
  failure, it no longer sets `errorMessage` when `Task.isCancelled`.

## Follow-up: two more bugs, found only once an admin account was actually tested

Everything above was verified with non-admin accounts, where
`fetchPermittedUserIDs(deviceId:)` fails immediately (`checkAdmin()`) and
never reaches its own query logic. The first time this was exercised with
a real administrator account, the broader "share with everyone who can see
the device" step *still* didn't work, `claude@...` saw the pet but not
its home, with no account anywhere short of admin-only restrictions to
blame. Two separate, previously-invisible bugs, both in `TraccarClient`,
both confirmed directly against the live server by isolating one variable
at a time:

- **Query parameter *order* determines which SQL table Traccar's own query
  builder resolves, independent of admin status or the values involved.**
  `GET /api/permissions?deviceId=X&userId=0` throws
  `org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "TC_DEVICE_USER" not
  found`; swapping to `?userId=0&deviceId=X`, same account, same values,
  only the order changed, returns the data correctly. The real table is
  evidently always addressed `tc_user_<other>`, and Traccar's resource only
  builds that name correctly when `userId` is the first parameter in the
  URL. `fetchPermittedUserIDs(deviceId:)`'s `queryItems` array order was
  fixed to put `userId` first.
- **`/api/permissions` returns UPPERCASE JSON keys** (`{"USERID":4,
  "DEVICEID":3}`), unlike every other Traccar endpoint seen in this
  codebase (camelCase, e.g. `TraccarDevice`'s `groupId`), evidently raw SQL
  column names leaking through instead of going through normal POJO
  serialization. `TraccarPermission`'s `Int?` properties, decoded with the
  usual camelCase assumption, silently became `nil` for every field instead
  of throwing a decode error, there is no such thing as a required field
  on an all-optional struct, so this was a *successful* decode into an
  empty, useless result, the worst kind of failure to diagnose from outside.
  Explicit `CodingKeys` now map to the real uppercase names, and the
  regression test's JSON fixture uses uppercase keys specifically so a
  reversion back to the default mapping fails loudly.

Both bugs independently produced the exact same symptom externally (no
grant happens, no error surfaces) as the already-documented "non-admin
can't call this endpoint" limitation above, which is exactly why they
went unnoticed for as long as they did: every observation looked
consistent with the already-known, already-explained cause. Only
isolating each variable one at a time against the live server (admin vs.
non-admin; parameter order; raw response bytes) told them apart.

**End-to-end re-verified after both fixes**, with a live device sending
real TLT-2H position reports through a home geofence and generating real
`geofenceExit`/`geofenceEnter` events: an admin edited the home once (no
content change, purely to re-run the sync), and a non-admin account that
had never been granted anything directly, only given ordinary device
access, then saw the identical geofence and the identical events as the
admin, with no manual permission grant in between.

## Consequences

- No more "diff existing permissions first" complexity: `POST
  /api/permissions` being idempotent means both grant steps can run
  unconditionally on every add *and* every edit, which also makes editing
  a home (even a no-op save) the repair path for one that predates this
  fix or whose sync partially failed.
- The admin-only ceiling on discovering/granting other users' access is a
  real Traccar limitation, not a LibrePaw shortcut, there is currently no
  way to fully close it from a non-admin account. Worth revisiting only if
  Traccar adds a less-privileged "who else can see this device" endpoint.
- This ADR's own first draft is itself an example of the exact mistake
  ADR-0012's "Consequences" warned about, Traccar behavior (`GET
  /api/users` returning "self") assumed rather than checked against a live
  server. Caught quickly this time only because multi-account testing
  surfaced it immediately; the fix was to go back and call the real
  endpoints directly rather than keep guessing from docs/forum posts.
