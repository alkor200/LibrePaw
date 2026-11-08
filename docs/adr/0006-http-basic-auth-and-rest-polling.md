# 6. HTTP Basic Auth and REST polling instead of cookie sessions / WebSocket

## Status

Accepted

## Context

Traccar supports two authentication styles for its REST API:

1. **Cookie-based sessions**: `POST /api/session` with form-encoded
   credentials returns a `JSESSIONID` cookie that must be stored and sent
   with every subsequent request, and re-established when it expires.
2. **HTTP Basic Authentication**: every request carries an `Authorization:
   Basic base64(email:password)` header; Traccar validates it per-request.
   No server-side session state, no cookie jar, no expiry handling.

Traccar also exposes a WebSocket endpoint (`/api/socket`) that pushes live
device/position updates, as an alternative to polling `GET /api/positions`.

## Decision

- **Authentication: HTTP Basic Auth**, sent on every request. The client is
  fully stateless between requests, there is no session to expire, refresh,
  or invalidate on the client side beyond discarding the stored credential.
- ~~**Live updates: REST polling**, not the WebSocket feed. `PetListViewModel`
  and `PetMapViewModel` refresh devices/positions on a timer (default 20s)
  while their view is visible, and pause when it is not
  (`.task`/`.onDisappear`).~~ **Superseded by
  [ADR-0013](0013-websocket-live-updates.md)**, which switches to the
  WebSocket feed now that it's known to need the same cookie session as
  media requests (ADR-0012). Kept here for history.

To validate credentials at login time, we call `GET /api/devices` rather than
`GET /api/session`. Traccar's `/api/session` `GET` endpoint only checks for an
existing *cookie-based* session and returns 404 unconditionally when there is
none, it ignores any `Authorization` header entirely, so it cannot be used
to validate Basic Auth credentials (confirmed against a live Traccar server;
`GET /api/devices` correctly returns 401 for bad credentials and 200 for
good ones). `/api/devices` is also the first call the app needs after login
regardless, so no extra round-trip is added.

## Consequences

- Significantly simpler client: no cookie storage, no 401-then-relogin
  retry logic, no session-expiry edge cases.
- The password (or a user-generated Traccar API token, if the server
  supports it) must be kept available to attach to every request, it is
  stored in the Keychain (see [0007](0007-keychain-credential-storage.md))
  and held in memory by the authenticated `TraccarClient` instance.
- Every request requires HTTPS to avoid sending Basic Auth credentials in
  the clear. The login screen warns (non-blocking) if the entered server URL
  uses `http://`, which may be acceptable for a local-network-only server
  during development but is discouraged.
- Polling means pet positions can be up to ~20 seconds stale and consumes
  periodic battery/network while a relevant screen is open. This is an
  explicit MVP trade-off; a future ADR can introduce the WebSocket feed
  (e.g. via `URLSessionWebSocketTask` in `TraccarKit`) behind the same
  repository protocol in `LibrePawKit`, without changing any view model.
- **Update:** [ADR-0012](0012-cookie-session-for-media-requests.md) adds one
  narrow exception to "Basic Auth only", Traccar's device media endpoint
  ignores Basic Auth and requires a cookie session instead. Every other
  endpoint is unaffected.
