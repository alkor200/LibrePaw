# 5. Modular architecture with local Swift packages

## Status

Accepted

## Context

We want a clean separation between "talking to Traccar", "pet tracking
domain logic", and "SwiftUI screens", so that:

- The domain and data layers can be unit tested without booting the app or a
  simulator.
- Dependencies only flow one way (presentation depends on domain, domain
  does not know about SwiftUI).
- The Traccar client is reusable in isolation, in line with
  [ADR-0002](0002-use-traccar-as-backend.md).

At the same time, this is an MVP: we deliberately avoid splitting into one
package per *feature* (e.g. separate packages for login, map, settings) since
that is premature for the current app size and would slow down iteration.

## Decision

Two local Swift packages, consumed by the `LibrePaw` app target:

1. **`TraccarKit`**, a standalone, LibrePaw-agnostic Swift client for the
   Traccar REST API. Knows about Traccar's wire format (devices, positions,
   sessions) and HTTP authentication. Has zero dependency on SwiftUI, zero
   knowledge of "pets". Could be extracted into its own repository later
   with no code changes.

2. **`LibrePawKit`**, the app's domain and data layer. Defines the app's
   own vocabulary (`Pet`, `PetPosition`, `PetStatus`), repository protocols,
   the authentication/session service, and Keychain-backed credential
   storage. Depends on `TraccarKit` to implement those repositories, but
   exposes only its own domain types, `TraccarKit`'s DTOs never leak past
   this layer.

The `LibrePaw` app target contains only SwiftUI views and view models
(MVVM), grouped by feature folder (`Features/Authentication`,
`Features/PetList`, `Features/Map`, `Features/PetDetail`,
`Features/Settings`). View models depend on `LibrePawKit` protocols, never
on `TraccarKit` directly.

Dependency direction:

```
LibrePaw (app, SwiftUI + view models)
   -> LibrePawKit (domain models, repository protocols, use cases)
        -> TraccarKit (Traccar REST client, DTOs)
```

## Consequences

- Business logic in `LibrePawKit` is testable with plain `swift test`, no
  simulator required.
- `TraccarKit` has no reason to ever import SwiftUI/UIKit/Combine, if it
  does, that is a sign of a layering mistake.
- As the app grows, a feature folder that outgrows the main target can be
  promoted to its own local package without changing this layering, that
  is a mechanical refactor we explicitly defer rather than doing upfront.
