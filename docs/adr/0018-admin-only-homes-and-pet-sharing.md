# 18. Restrict adding homes and sharing a pet to administrator accounts

## Status

Accepted — builds on [ADR-0017](0017-geofence-user-permissions-for-multi-user-households.md).
The "Homes management is hidden from non-admins entirely" decision below is
superseded by [ADR-0019](0019-reenable-non-admin-homes-with-a-visibility-notice.md),
which shows the screen to everyone again with an in-app notice instead.
**Share `<Pet>` staying admin-only is unaffected** and still stands — see
ADR-0019's Status for why.

## Context

ADR-0017 established, and then confirmed with two separate non-admin
accounts against a live server, that a non-admin creating a home only ever
makes it visible to themselves — and that this isn't limited to the Homes
screen: `fetchExcursions` resolves which geofences count as "home" via the
same per-user-filtered `GET /api/geofences?deviceId=` call, so a user
without geofence permission gets a silently empty excursions list too, with
no error to distinguish it from "no excursions happened."

Checked directly against a live server, with a fresh geofence and real
geofence-crossing events (fed in via a simulated GPS tracker over Traccar's
TLT-2H/Mictrack protocol) and two separate non-admin accounts that both
already had ordinary device-level access to the same pet:

- The account that didn't create the geofence got `[]` from both
  `GET /api/geofences?deviceId=` and `GET /api/reports/events?type=
  geofenceExit/geofenceEnter` for it — despite the events genuinely
  existing and being visible to the creating account on the identical
  query.
- Neither account could grant the *other* permission to anything, geofence
  or device — `POST /api/permissions` for an object you don't already
  manage returns `java.lang.SecurityException: User access denied`,
  regardless of which side of the link is "self."
- This is deliberate Traccar design, not a gap Scentrail can route around:
  official docs describe sharing an object as an explicit admin action
  ("As an admin you can share any objects including geofences from
  Settings > Users menu"), and there is no server config setting that
  changes this.

Scentrail's target user (ADR-0002) already always has an admin account —
they're the one who stood up their own Traccar server. Family members using
Scentrail against that same server are typically non-admin accounts the
admin shared devices with.

## Decision

- `PetRepository` gains `isCurrentUserAdministrator()`
  (`TraccarClient.fetchCurrentUser().administrator`, reusing the
  cookie-session call from ADR-0017) and `sharePet(forPetID:withEmail:)`.
- **Homes management is hidden from non-admins entirely**, not just the
  "Add" action within it: `PetDetailView` only shows the "`<Pet>`'s Homes"
  row for an admin account, so a non-admin never reaches `HomesView` at
  all — there's nothing useful for them to do there (they can't make a
  home visible to anyone but themselves), and a visible-but-disabled affordance
  would invite confusion a hidden one doesn't. `HomesView`/`HomesViewModel`
  accordingly carry no admin check of their own; being unreachable for a
  non-admin makes one unnecessary.
  **(Reversed by ADR-0019 — the screen is shown to everyone again, with an
  in-app notice instead of being hidden.)**
- New **"Share `<Pet>`"** action on `PetDetailView`, admin-only, opening
  `SharePetView` — a single email field that resolves to a Traccar user via
  `GET /api/users?keyword=` (admin-only, but reliable for an admin — see
  ADR-0017's finding on what this endpoint returns for non-admins) and
  links them to the device. This is the in-app equivalent of what an admin
  would otherwise do in Traccar's own Settings > Users screen.
- Both gates **hide the affordance rather than block the underlying call**:
  there's no separate enforcement in `TraccarPetRepository` beyond what
  Traccar's own API already enforces server-side. If admin status can't be
  determined (network hiccup), both default to non-admin — hiding the
  option rather than offering something that would only partially work.

## Consequences

- A non-admin has no in-app path to homes at all now, including editing one
  — a stricter cut than ADR-0017 originally drew (which still allowed
  editing). Consistent with the household model from the Context above:
  Scentrail's non-admin accounts are there to *see* what the admin set up,
  not manage it.
  **(Reversed by ADR-0019 — see this ADR's Status.)**
- `isCurrentUserAdministrator()` and `loadAdministratorStatus()` are called
  once per screen visit (`HomesView`, `PetDetailView`), not cached across
  the app — consistent with Scentrail's "thin client" scope (ADR-0002) and
  the precedent set by `lifetimeExcursionStats` rather than introducing new
  session-wide state.
- `sharePet` also walks the pet's existing homes and grants the new user
  geofence permission for each, best-effort, right after the device grant —
  since the caller reaching this screen is already confirmed admin, this
  closes the gap immediately rather than leaving the new household member
  unable to see excursions until someone happens to edit a home later.
