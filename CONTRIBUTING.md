# Contributing to Scentrail

Thanks for your interest in Scentrail! This project is an MVP and welcomes
contributions, big or small.

## Before you start

- For anything beyond a small fix, please open an issue first to discuss the
  approach - especially if it touches an existing
  [Architecture Decision Record](docs/adr). This avoids wasted work on a pull
  request that conflicts with a settled decision.
- If your change *does* reverse or supersede an existing ADR, say so in the
  issue/PR and include a new ADR as part of the change (see
  [ADR-0001](docs/adr/0001-record-architecture-decisions.md)).

## Project setup

See [README.md](README.md#getting-started).

## Code style

- All code and comments are in English.
- SwiftUI only, no UIKit view controllers (see
  [ADR-0003](docs/adr/0003-ios-platform-and-ui-framework.md)).
- Follow the existing layering: `TraccarKit` → `ScentrailKit` → `Scentrail`
  app target. Don't let `TraccarKit` types (its DTOs, `TraccarClient`) leak
  past `ScentrailKit` (see [ADR-0005](docs/adr/0005-modular-architecture-with-local-swift-packages.md)).
- Prefer Apple's native UI components and interaction patterns (`List`,
  `Form`, `NavigationStack`, system colors/SF Symbols) over custom-built
  equivalents.
- No third-party dependencies without discussion first - part of the appeal
  of this project is a small, auditable dependency footprint.

## Tests

- `TraccarKit` and `ScentrailKit` changes should come with `swift test`
  coverage in the corresponding package.
- View model changes should come with a test in `ScentrailTests` using the
  fakes in `ScentrailTests/Fakes.swift` (or new fakes alongside them).

## Pull requests

- Keep PRs focused on one change.
- Describe *why*, not just *what* - the same spirit as our ADRs.
- Make sure `xcodegen generate` still produces a project that builds, and
  that `swift test` passes in both packages.
