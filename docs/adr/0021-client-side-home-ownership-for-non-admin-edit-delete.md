# 21. Track home ownership client-side, restrict non-admin edit/delete to the creator

## Status

Superseded by [ADR-0023](0023-follow-traccars-own-permission-model.md). Originally accepted as an amendment to [ADR-0019](0019-reenable-non-admin-homes-with-a-visibility-notice.md).

## Context

Asked to test every feature as both an admin and a non-admin account, with
particular attention to permissions, especially what happens when a
non-admin edits a home. Tested directly against a live server with the
same two accounts used throughout ADR-0017/0018/0019 (one admin, one
non-admin, both with ordinary device access to the same pet, one already
having an admin-shared home visible to it):

- `PUT /api/geofences/{id}`: the non-admin account could edit a geofence
  it only had *view* permission to, not one it created, and the edit
  succeeded (`200`).
- `DELETE /api/geofences/{id}`: same account, same geofence, succeeded
  (`204`) too, deleting the shared home entirely, for every account that
  could see it, not just unsharing it for the one account that deleted it.

Traccar's permission model draws no distinction between "can see this
geofence" and "can manage this geofence": a `{userId, geofenceId}`
permission link, the same one `syncGeofenceVisibility` (ADR-0017) grants
to every household member so they can *see* a home, also happens to be
sufficient for that same account to edit or delete it outright. This
wasn't visible in ADR-0017/0018/0019's testing because those rounds never
had a non-admin try to touch a home it didn't itself create.

Reproduced the same thing through the app's own UI, not just curl: a
non-admin opening a home an admin had set up saw the same trash icon and
editable fields as the admin does, with the existing visibility notice
even incorrectly telling them "Only visible to you" about a home that
plainly wasn't, since the notice only ever distinguished admin/non-admin,
never who actually created the specific home being looked at.

## Decision

- `HomeGeofence` gains `ownerUserID: Int?`, Traccar itself has no concept
  of geofence ownership, so LibrePaw stamps its own: a `librepawOwnerId`
  attribute (alongside the existing `scentrailHome` marker) holding the
  creating account's Traccar user id, written once at
  `addHomeGeofence` time and carried forward unchanged on every
  `updateHomeGeofence` (which replaces `attributes` wholesale, so the
  existing value has to be read back first via the new
  `TraccarClient.fetchGeofence(id:)` and re-included, otherwise an edit
  would silently erase it).
- `PetRepository` gains `currentUserID()`, so the app layer can compare
  the signed-in account against a home's `ownerUserID` without needing to
  know anything about Traccar's `administrator` flag for this specific
  check.
- `HomesViewModel.canManage(_:)`: `true` for an admin always, otherwise
  only for the account whose id matches `ownerUserID`. A home with no
  recorded owner (anything created before this shipped) defaults to
  **not** manageable by a non-admin, Traccar puts no ceiling on who can
  edit or delete a geofence they can merely see, so an unknown owner has
  to be treated as "not mine" rather than risk a non-admin deleting a
  home the rest of the household depends on.
- `HomesView`: swipe-to-delete is disabled per row via `.deleteDisabled`
  for any home `canManage` says no to, and a lock icon marks that row so
  it's visible before trying, not just blocked silently.
- `SetHomeView`/`SetHomeViewModel`: the same check gates everything, the
  trash button is hidden entirely (`canManage == true` required to show
  it, same "hide rather than offer a broken affordance" reasoning as
  ADR-0018's `Share <Pet>`), the name field and radius slider are
  disabled, dragging the map no longer moves the pin, and the Save button
  is hidden outright rather than shown disabled, there's nothing at all
  the signed-in account can do on this screen for a home it doesn't own.
  `save()`/`confirmDelete()` also check `canManage` themselves before
  calling the repository, not just relying on the UI being disabled.
- The visibility notice (both on the list and inline in the edit screen)
  now distinguishes three states instead of two: admin (applies to
  everyone), non-admin viewing their own home (private to them, same
  wording as ADR-0019), and non-admin viewing someone else's home (read
  only, explains why).

## Consequences

- A household's pre-existing homes (created before this shipped) have no
  recorded owner, so a non-admin loses edit/delete access to any of them
  even ones they personally set up previously, until an admin edits each
  one once (which now also carries forward... nothing, since there's
  nothing yet to carry forward, an admin's own edit doesn't retroactively
  assign an owner). Judged an acceptable one-time cost given the
  alternative, defaulting an unknown owner to "manageable", reopens
  exactly the bug this ADR exists to close.
- This is a client-side restriction only, not a server-side one, Traccar
  itself still allows the underlying `PUT`/`DELETE` for anyone with
  geofence-level view access. Anyone calling the Traccar API directly
  (rather than through LibrePaw) bypasses this entirely, the same
  caveat ADR-0018 already carries for its own admin-only gates.
- `createGeofence`/`updateGeofence`'s `attributes` parameter widened from
  `[String: Bool]` to `[String: JSONValue]` to carry a numeric owner id
  alongside the existing boolean marker, `JSONValue` gained `Encodable`
  conformance (it was decode-only before) to support this.
