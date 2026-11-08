# 23. Follow Traccar's own permission model, not a client-side one

## Status

Accepted, supersedes [ADR-0021](0021-client-side-home-ownership-for-non-admin-edit-delete.md).

## Context

Asked to stop layering an app-level restriction on top of Traccar's own
permissions: whatever Traccar's actual permission model allows an account
to do, Scentrail should allow too, and whatever it doesn't allow,
Scentrail shouldn't offer in the first place, rather than let the user
find out from a server error. ADR-0021's client-side home ownership
(`scentrailOwnerId`, restricting edit/delete to whoever created a given
home) was exactly the kind of extra restriction this asks to remove,
Traccar itself never drew that distinction.

Tested every Traccar `User` permission flag directly against a live
server (curl, both the admin and non-admin test accounts, toggling flags
on the non-admin account via the admin one and re-testing):

- `administrator`: bypasses every other check. An admin can `GET`/`PUT`/
  `DELETE` any device or geofence on the server, even ones it has no
  permission link to at all, and is the only account that can create a
  permission link for *another* user (`POST /api/permissions` with a
  different `userId` than the caller's own), confirmed both ways:
  non-admin gets `SecurityException: User access denied` attempting it.
- `readonly`: blocks every write (`POST`/`PUT`/`DELETE`, devices and
  geofences alike) with `SecurityException: Write access denied`. Reads
  still work. Creating a geofence while `readonly` also still auto-links
  the creator to it when it succeeds (`readonly=false`), same as before.
- `deviceReadonly`: blocks writes to devices specifically only, both
  `PUT /api/devices/{id}` and `POST /api/devices/{id}/image` (the photo
  upload step from ADR-0011). Geofences are unaffected, confirmed by
  toggling only this flag and creating a geofence successfully.
- `disableReports`: blocks `GET /api/reports/events`, the only endpoint
  excursions and the trail are built from (`fetchExcursions` pairs its
  enter/exit events, see ADR-0014/0016), with `SecurityException:
  Operation restricted`. Nothing else Scentrail calls uses `/api/reports`.
- Confirmed separately, without any ownership check at all: a non-admin
  with ordinary view access to a geofence or device it didn't create can
  edit or delete it outright (the same finding ADR-0021 made, now acted
  on differently, see Decision).

## Decision

- `AccountPermissions` (new, `ScentrailKit/Domain`), four booleans
  computed from `TraccarUser`'s now-widened set of fields
  (`readonly`, `deviceReadonly`, `disableReports`, alongside the existing
  `administrator`): `isAdministrator`, `canManageHomes`
  (`administrator || !readonly`), `canManageDevicePhoto`
  (`administrator || (!readonly && !deviceReadonly)`), `canViewExcursions`
  (`administrator || !disableReports`).
- `PetRepository.isCurrentUserAdministrator()`/`currentUserID()` replaced
  by a single `currentUserPermissions() async throws -> AccountPermissions`,
  one `fetchCurrentUser()` call instead of two.
- `HomeGeofence.ownerUserID` removed entirely, along with the
  `scentrailOwnerId` attribute Scentrail used to stamp on every home it
  created (ADR-0021's mechanism). `addHomeGeofence`/`updateHomeGeofence`
  no longer read or write it.
- `HomesViewModel.canManage(_ home:)` (per-home, ownership-based) replaced
  by `canManageHomes` (one value for every home, since it no longer
  depends on who created which one, just the signed-in account's own
  `readonly` flag). Same change in `SetHomeViewModel`, which also drops
  the old "adding is always allowed, only editing was gated" special
  case, since `readonly` blocks `POST` just as much as `PUT`/`DELETE`.
- `HomesView`'s per-row lock icon (ADR-0021's "someone else's home") is
  gone, since there's no longer a per-home distinction to show, a
  `readonly` account simply can't add, edit, or delete *any* home, which
  its visibility notice now says plainly instead. The "Add Home" buttons
  (toolbar and empty-state) and swipe-to-delete are hidden/disabled
  together, uniformly, once `canManageHomes` resolves to `false`.
- `PetDetailView`'s avatar is only a button (opening the photo editor)
  when `canManageDevicePhoto` is `true`, a plain image otherwise, same
  reasoning as the rest of this ADR: don't offer an affordance that would
  just fail server-side.
- `PetDetailView`'s Trail and Excursions rows are hidden together when
  `canViewExcursions` is `false`, rather than leading to a screen that
  can only ever show an error.
- Sharing a pet stays admin-only exactly as ADR-0018 already had it,
  confirmed still accurate by the live test above, nothing to change
  there.

## Consequences

- A non-admin account with ordinary permissions (the common case) now
  sees no difference at all from an admin as far as editing/deleting
  homes goes, matching what Traccar itself has always allowed. The
  ownership restriction ADR-0021 added is gone, anyone who can see a home
  can manage it, same as Traccar's own web UI would let them.
- The four `AccountPermissions` flags are a direct read of Traccar's own
  settings, nothing in Scentrail adds a stricter rule on top (aside from
  sharing staying admin-only, which is Traccar's own restriction, not
  Scentrail's). Someone who wants a Scentrail user restricted to viewing
  only sets `readonly` (and/or `deviceReadonly`, `disableReports`) on
  that Traccar account directly, there's no separate Scentrail-side
  setting to keep in sync with it.
- `scentrailOwnerId` attributes already written on existing geofences by
  a pre-ADR-0023 build are simply never read again, harmless leftover
  data, no migration needed.
