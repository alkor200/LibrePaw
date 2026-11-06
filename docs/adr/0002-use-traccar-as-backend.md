# 2. Use Traccar as the tracking backend

## Status

Accepted

## Context

Scentrail needs a server that receives GPS positions from pet-tracking
hardware (collars/trackers) and exposes them to client apps. Building and
operating a custom GPS ingestion backend (device protocols, storage,
geofencing, historical reporting) is a large undertaking and out of scope for
an MVP.

[Traccar](https://www.traccar.org/) is a mature, open source (Apache 2.0)
GPS tracking platform that already:

- Speaks 100+ hardware protocols used by GPS trackers.
- Stores device, position and event history.
- Exposes a documented REST API (`/api/...`) and a WebSocket feed for live
  updates.
- Is self-hostable, which matches the open source, privacy-respecting goals
  of this project (pet owners can run their own server).

## Decision

Scentrail is a client application for an existing, user-supplied Traccar
server. We do not build or vendor any server-side code. Traccar's domain
language is reused directly:

- A Traccar **device** represents a pet's tracker/collar.
- A Traccar **position** represents one GPS fix.

The app's domain layer (`ScentrailKit`) renames "device" to **Pet** at the
boundary, since that is the concept the end user cares about — but the
underlying wire format and REST semantics are Traccar's, unmodified.

## Consequences

- Users must have access to a running Traccar server (self-hosted or
  hosted-by-a-third-party) and at least one configured tracker device.
- The app's networking layer (`TraccarKit`) is intentionally decoupled from
  Scentrail-specific concepts, so it can plausibly be reused or extracted as
  a standalone Traccar Swift client package later (see
  [0005](0005-modular-architecture-with-local-swift-packages.md)).
- We inherit Traccar's data model and limitations (e.g. no built-in concept
  of "species" or "pet photo" — those would need to be layered on top in a
  future iteration, e.g. via Traccar's free-form device attributes).
- We depend on Traccar's API stability. We target the stable, documented
  REST endpoints (`/api/session`, `/api/devices`, `/api/positions`) which
  have been stable across Traccar releases.
