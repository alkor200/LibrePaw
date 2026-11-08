# 9. Manual dependency injection via a single `AppDependencies` container

## Status

Accepted

## Context

View models need access to `LibrePawKit` services (`AuthenticationService`,
`PetRepository`). We need a way to construct and hand those dependencies to
views that is testable (injectable fakes) without pulling in a DI framework.

## Decision

A single plain struct, `AppDependencies`, constructed once in
`LibrePawApp.swift`, holds the concrete service instances and is passed
explicitly down the view hierarchy as an initializer parameter. View models
are plain `@Observable` classes constructed by their parent view, receiving
dependencies as initializer parameters (protocol types, not concretes) -
not via `@Environment`, property wrappers, or a service locator.

```swift
@main
struct LibrePawApp: App {
    @State private var dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
```

Tests construct view models directly with fake/mock implementations of the
`LibrePawKit` protocols, no container, no framework, no reflection-based
resolution.

## Consequences

- No third-party DI framework dependency.
- Dependency graphs are explicit and traceable by reading initializers.
- `AppDependencies` is the one place that knows how to wire a "live" app vs.
  a "preview/test" app (e.g. SwiftUI preview providers use
  `AppDependencies.preview()` with in-memory fakes).
- This does mean some initializer parameter lists grow as the app gains
  dependencies; if that becomes unwieldy, revisit with a new ADR rather than
  silently introducing a framework.
