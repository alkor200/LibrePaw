# 8. The app never reads the iPhone's own location in the MVP

## Status

Superseded by [ADR-0010](0010-device-location-for-distance-and-find-pet.md)

## Context

Scentrail displays the location of *pets*, which comes entirely from GPS
tracker hardware reporting into Traccar. It is tempting to also show "my
current location" on the map for context (e.g. "how far is my dog from me"),
which would require `CoreLocation` and the
`NSLocationWhenInUseUsageDescription` permission prompt.

## Decision

The MVP requests **no device permissions at all** - no location, no
notifications, no camera/photo library. The map shows pet positions only.

## Consequences

- Simpler, faster first-run experience: no permission dialogs to explain or
  handle denial/"don't allow" flows for.
- Smaller `Info.plist`, smaller privacy manifest surface, easier App Store
  privacy nutrition label.
- "Distance from me" / "directions to my pet" is explicitly deferred to a
  future iteration, at which point it should get its own ADR covering the
  permission request flow and denied-permission UX.
