# 12. Use a cookie session for media requests only

## Status

Accepted, amends [ADR-0006](0006-http-basic-auth-and-rest-polling.md)

## Context

While building pet photo support ([ADR-0011](0011-pet-avatar-from-traccar-photo-attribute.md)),
`fetchData(from:)` kept returning `401 Unauthorized` on
`/api/media/<uniqueId>/<filename>` even with verified-correct credentials.
Testing directly against a live Traccar server confirmed:

- `GET /api/media/...` with a correct `Authorization: Basic ...` header →
  `401`, served by Jetty itself (a generic Jetty error page, not a Traccar
  JSON error), meaning this path isn't even reaching Traccar's own
  Basic-Auth-aware request filter.
- `POST /api/session` with form-encoded credentials → `200`, sets a
  `JSESSIONID` cookie.
- The same `GET /api/media/...` request, with that cookie attached instead
  → `200` with the actual image bytes.

So Traccar's media files are protected by a *different* authentication path
than the rest of the REST API: a cookie-based session, not Basic Auth. This
is the same kind of undocumented, endpoint-specific quirk as the one
ADR-0006 already found in `GET /api/session` (which ignores Basic Auth
entirely), Traccar's various endpoints are not uniformly guarded by the
same filter.

## Decision

`TraccarClient.fetchData(from:)`, used only for fetching device media -
lazily establishes a cookie session the first time it's called, by POSTing
form-encoded credentials to `/api/session`, before issuing the actual GET.
`URLSession`'s built-in cookie jar then attaches the resulting `JSESSIONID`
automatically to that and subsequent requests to the same host, no manual
cookie handling needed. If a request still comes back `401` after a session
was believed established (e.g. it expired), the client re-establishes the
session once and retries.

Every other endpoint (`/api/devices`, `/api/positions`) is unaffected and
continues to use only HTTP Basic Auth per ADR-0006, this cookie session
exists solely to satisfy `/api/media`'s particular requirement, and is
never relied upon elsewhere.

## Consequences

- `TraccarClient` is no longer *fully* stateless as ADR-0006 originally
  described, it now holds one bit of actor state (`hasCookieSession`) and,
  transitively, relies on `URLSession`'s cookie jar. This is scoped
  narrowly: nothing outside `fetchData(from:)` depends on or is affected by
  that cookie.
- The first photo fetch per `TraccarClient` instance costs one extra
  round-trip (the session POST); subsequent photo fetches on the same
  instance reuse the existing cookie.
- Because `TraccarClient` instances are typically constructed with
  `URLSession.shared`, its cookie jar is shared process-wide, logging out
  and back in as a different user on the same server could briefly reuse a
  stale cookie until the first `401`-triggered re-login corrects it. This is
  an acceptable MVP trade-off; a future iteration could have `logOut()`
  explicitly clear cookies for the server's host.
- This is the second time an assumption about Traccar's API went unverified
  into an ADR (see ADR-0011's revision history) before being caught by
  real-world testing. Future ADRs touching Traccar's behavior should be
  checked against a live server or the Traccar/traccar-web source before
  being written down as fact.
