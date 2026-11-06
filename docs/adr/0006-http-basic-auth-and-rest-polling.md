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
  fully stateless between requests — there is no session to expire, refresh,
  or invalidate on the client side beyond discarding the stored credential.
- **Live updates: REST polling**, not the WebSocket feed. `PetListViewModel`
  and `PetMapViewModel` refresh devices/positions on a timer (default 20s)
  while their view is visible, and pause when it is not (`.task`/`.onDisappear`).

We do still call `GET /api/session` once after login purely to *validate*
the credentials and fetch the current user's profile — not to establish a
cookie session.

## Consequences

- Significantly simpler client: no cookie storage, no 401-then-relogin
  retry logic, no session-expiry edge cases.
- The password (or a user-generated Traccar API token, if the server
  supports it) must be kept available to attach to every request — it is
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
  repository protocol in `ScentrailKit`, without changing any view model.
