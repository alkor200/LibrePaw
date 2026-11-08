# 1. Record architecture decisions

## Status

Accepted

## Context

We need to record the architectural decisions made on this project so that
contributors (including our future selves) understand *why* the codebase
looks the way it does, not just what it looks like. This is especially
important for an open source project, where contributors join without the
context that exists in a team's shared memory.

## Decision

We will use Architecture Decision Records (ADRs), as described by Michael
Nygard, and keep them in `docs/adr`. Each ADR is numbered sequentially and
immutable once accepted - if a decision changes, a new ADR supersedes the old
one rather than editing it in place.

Format per ADR:

- Title
- Status (Proposed / Accepted / Superseded by ADR-000X)
- Context
- Decision
- Consequences

## Consequences

Anyone proposing a significant architectural change should add a new ADR as
part of the pull request, rather than only discussing it in a PR description
or chat.
