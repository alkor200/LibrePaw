# 19. Re-enable home management for non-admin accounts, with an in-app visibility notice

## Status

Accepted — partially supersedes [ADR-0018](0018-admin-only-homes-and-pet-sharing.md):
the "Homes management is hidden from non-admins entirely" decision is
reversed below. ADR-0018's other decision — **Share `<Pet>`** staying
admin-only — still stands; Traccar genuinely has no non-admin path for
granting another account access to anything, so hiding that entry point is
unaffected by this ADR.

## Context

ADR-0018 hid the "`<Pet>`'s Homes" entry point entirely for non-admin
accounts, reasoning that a home they set up would only ever be visible to
themselves (ADR-0017), so there was "nothing useful for them to do there."

Revisited: that's true, but it's not actually a reason to hide the screen —
a non-admin managing their *own* private home, with their *own* derived
excursions, is a legitimate use on its own (e.g. someone tracking a pet
that's genuinely only ever in their care), not just a degraded version of
the admin flow. The real requirement is that this limitation be stated
clearly in the UI, not papered over by hiding the feature.

## Decision

- `PetDetailView` shows the "`<Pet>`'s Homes" row to every account again,
  admin or not — only **Share `<Pet>`** stays gated behind
  `viewModel.isAdministrator`.
- `HomesViewModel` and `SetHomeViewModel` each gained their own
  `isAdministrator` (`Bool?`, `nil` until `loadAdministratorStatus()`
  resolves — same best-effort, no-error-surfaced pattern as
  `PetDetailViewModel`'s). Nothing changes server-side; this only drives
  which notice to show.
- Both `HomesView` (above the list/empty state) and `SetHomeView` (inside
  the add/edit controls card, at the actual point of action) show a short
  notice once admin status is known:
  - Admin: "homes you add here are visible to everyone with access to
    `<Pet>`."
  - Non-admin: "Homes you add here — and the excursions they create — are
    only visible to you. Ask an admin to add a home if it should apply to
    everyone."

  Showing it in both places is deliberate: the list is where someone
  revisits to understand what's already there, the add/edit screen is
  where the decision to add one actually gets made.
- No change to `TraccarPetRepository` — `addHomeGeofence`/
  `updateHomeGeofence`'s `syncGeofenceVisibility` (ADR-0017) already
  degrades gracefully for a non-admin (it grants itself, and silently can't
  reach the device-wide grant step), so there's no new code path here, only
  a UI one.

## Consequences

- A non-admin can now manage their own homes again, same as before
  ADR-0018, but with the limitation stated up front instead of discovered
  by a household member wondering why a sibling's new home never shows up
  for them.
- `isAdministrator` is now fetched independently by three view models
  (`PetDetailViewModel`, `HomesViewModel`, `SetHomeViewModel`) rather than
  passed down from the screen that already knows it — consistent with the
  existing "fetch per screen, don't introduce shared state" precedent
  (ADR-0018's own Consequences section), at the cost of one extra
  `GET /api/session` round trip per screen visit.
