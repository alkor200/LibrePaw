# 13. Live updates via Traccar's WebSocket feed

## Status

Accepted, supersedes the polling half of [ADR-0006](0006-http-basic-auth-and-rest-polling.md)

## Context

ADR-0006 chose REST polling over Traccar's WebSocket feed for the MVP, to
keep the client simple. Having since discovered (ADR-0012) that Traccar's
media endpoint needs a cookie session rather than Basic Auth, the same
question came up again for `/api/socket`, and was worth re-verifying
rather than assuming either way.

Tested directly against a live server:

- `GET /api/socket` with a WebSocket upgrade request and Basic Auth →
  `200 OK`, no upgrade, the server silently ignores the Upgrade header.
- The same request with a cookie session (from `POST /api/session`) →
  `101 Switching Protocols`, followed by a stream of JSON messages like
  `{"positions":[...]}` (on a new fix), `{"devices":[...]}` (on a status
  change), and `{}` as a periodic keep-alive.

So `/api/socket` has the same authentication requirement as `/api/media`
(ADR-0012), not a new problem, just the same one found a second place.
With live updates now practical to implement, and the user explicitly
requesting them, this revisits ADR-0006's polling choice.

## Decision

`TraccarClient.liveUpdates(reconnectDelay:)` opens the WebSocket (reusing
the same lazily-established cookie session as media requests) and yields a
decoded `TraccarSocketUpdate` per message. Transient drops are retried
automatically after `reconnectDelay` (default 5s), the stream only
finishes on an unrecoverable error or when the caller stops consuming it.

`PetRepository.livePetUpdates() -> AsyncThrowingStream<[Pet], Error>` is the
`ScentrailKit`-level API consumed by the app. `TraccarPetRepository`
implements it as a hybrid:

1. One initial snapshot via the existing REST calls (`fetchDevices` +
   `fetchLatestPositions`), a known-reliable bootstrap, independent of
   whatever the socket happens to send first.
2. Then, for each live message, merges any `devices`/`positions` it
   contains into an in-memory dictionary keyed by device id, and yields a
   fresh full pet list whenever something actually changed (keep-alives are
   silently skipped).

`PetListViewModel`, `PetMapViewModel`, and `FindPetViewModel` all replaced
their 10–20s polling timers with a subscription to this stream
(`startLiveUpdates()`/`stopLiveUpdates()`, started/stopped exactly where
`startPolling()`/`stopPolling()` used to be). Pull-to-refresh on the pet
list still does one direct `fetchPets()` call, independent of the stream.

Every other endpoint is unaffected, `/api/devices`, `/api/positions`, etc.
continue to use only HTTP Basic Auth per ADR-0006.

## Consequences

- Pet positions now update within roughly a second of Traccar receiving
  them, instead of being up to ~20s stale.
- One long-lived connection per visible screen (Pets, Map, or Find Pet)
  instead of a periodic request, less network chatter overall, though the
  connection itself stays open for as long as the screen is visible.
- `TraccarClient`'s automatic reconnect-and-retry means a transient network
  blip is invisible to the UI; a *persistent* failure (e.g. a revoked
  password) retries forever rather than surfacing, acceptable for the MVP
  since by the time a live stream is running, login already validated the
  credentials once; this would only bite if they changed mid-session.
- `URLSessionWebSocketTask` can't be driven through `MockURLProtocol` (it
  bypasses registered `URLProtocol` classes entirely), so `decodeSocketMessage`,
  the one piece of parsing logic in this path, is tested directly against
  the exact JSON shapes verified above, while the connection/reconnect
  logic itself was verified against a live server rather than in the
  automated suite.
