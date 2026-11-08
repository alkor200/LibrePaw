# 3. Target iOS 17+ with SwiftUI only

## Status

Accepted

## Context

We need to pick a minimum deployment target and a UI framework for a new,
greenfield iOS app with no legacy constraints.

## Decision

- **Minimum deployment target: iOS 17.**
- **UI framework: SwiftUI exclusively**, no UIKit view controllers, no
  Storyboards/XIBs.
- **State management: the Observation framework** (`@Observable`,
  `@Bindable`) introduced in iOS 17, instead of the older
  `ObservableObject`/`@Published` Combine-based approach.
- **Concurrency: Swift Concurrency** (`async`/`await`, actors) exclusively.
  No completion-handler APIs, no Combine for networking.
- **Maps: the SwiftUI `Map` view from MapKit** (iOS 17's `Map(initialPosition:)`
  / `MapContentBuilder` API), not the older `MKMapView` UIViewRepresentable
  wrapper.

As a consequence, we also adopt Swift 6 language mode / strict concurrency
checking in all targets and packages.

## Consequences

- We give up compatibility with iOS 15/16 users. For a new open source MVP
  with no existing user base, this is an acceptable trade-off in exchange for
  a significantly smaller, more modern codebase (no `ObservableObject`
  boilerplate, no `@MainActor` ambiguity, no UIViewControllerRepresentable
  bridging).
- Contributors need Xcode 15+ (Xcode 16+ recommended for full Swift 6 tooling)
  to build the project.
- All new features should default to SwiftUI-native patterns; if a feature
  genuinely requires UIKit (e.g. a capability with no SwiftUI equivalent yet),
  that should be justified in a new ADR rather than introduced silently.
