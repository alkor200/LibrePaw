# 11. Pet avatar from Traccar's built-in device image

## Status

Accepted (revised - see Context)

## Context

Map pins and the pet detail screen should show something more recognizable
than a generic map marker - ideally a photo of the actual pet.

This ADR originally assumed Traccar had no photo concept and specified a
manual `photo` attribute holding a direct image URL. That assumption was
wrong and was never verified against Traccar's actual behavior - a bug
report from real-world testing (a photo set in Traccar didn't show up in
Scentrail) prompted inspecting the
[traccar-web](https://github.com/traccar/traccar-web) client source
directly, which showed:

- Traccar's web UI already has a built-in **device image upload** control
  (in the device edit dialog) - owners don't need to touch raw attributes.
- Uploading calls `POST /api/devices/{id}/image`; the server stores the file
  and returns its generated filename, which the client saves as the
  device's `deviceImage` attribute (not `photo`).
- The image is served back at `/api/media/<uniqueId>/<filename>` - keyed by
  the device's `uniqueId`, not its numeric id. This endpoint turned out to
  need its *own* authentication mechanism (a cookie session, not Basic
  Auth) - see [ADR-0012](0012-cookie-session-for-media-requests.md) for that
  second round of verification-against-reality.

## Decision

- `PetMapping` reads the `deviceImage` attribute (a filename) and, combined
  with the device's `uniqueId` and the server's base URL, builds
  `Pet.photoURL = <serverURL>/api/media/<uniqueId>/<deviceImage>`.
- Because that endpoint requires its own authenticated request (see
  ADR-0012), `Pet.photoURL` is **not** fetched with a plain
  `AsyncImage(url:)` (which cannot attach custom headers or cookies).
  Instead, `PetRepository` gains `fetchPhoto(for pet:) async throws ->
  Data?`, implemented by `TraccarPetRepository` via a new
  `TraccarClient.fetchData(from:)` (restricted to the client's own server
  host, as a safeguard against ever sending credentials elsewhere).
- `PetAnnotationView` loads the photo through this repository method into a
  `UIImage`, falling back to a tinted paw icon when there is none or it
  fails to load.
- Owners set a pet's photo the normal way: Traccar's web UI → **Edit
  Device** → upload an image. No manual attribute editing needed.

## Consequences

- No new backend/storage requirement on Scentrail's side - the upload flow
  is entirely Traccar's existing feature; Scentrail only *displays* it.
- The photo-loading path now goes through the same layered architecture as
  everything else (`TraccarKit` → `ScentrailKit` → app), rather than being a
  special case that bypasses `PetRepository` - consistent with ADR-0005.
- `UIImage`-based loading has no persistent cache beyond what
  `URLSession`'s default cache gives `TraccarClient.fetchData`; acceptable
  for the MVP given photos rarely change and devices are few. A future
  iteration could add explicit caching if this becomes a problem.
- This ADR is a good example of why ADR context should be verified against
  the real system rather than assumed - the original version of this
  decision shipped without ever being checked against Traccar's actual API
  behavior.
