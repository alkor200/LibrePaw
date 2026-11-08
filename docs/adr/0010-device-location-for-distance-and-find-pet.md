# 10. Request device location for distance display and a "Find Pet" compass

## Status

Accepted, supersedes [ADR-0008](0008-no-device-location-access-in-mvp.md)

## Context

ADR-0008 deliberately kept the MVP free of any device-permission prompts.
Once using the app day-to-day, the obvious next question is "how far away is
my pet, and which way do I walk?", the same job Apple's Find My does for an
AirTag with its rotating-arrow proximity view. Answering that requires
knowing the user's own position (and, for the arrow, their compass heading),
which ADR-0008 explicitly ruled out.

## Decision

The app now requests **"When In Use" location access** (not "Always") the
first time the Map tab or a "Find Pet" screen is opened, not proactively at
launch. A new app-layer `LocationService` (`LibrePaw/Sources/Common`) wraps
`CLLocationManager` and exposes the user's coordinate, compass heading, and
authorization state.

Two features consume it:

1. **The Map tab** shows the user's own position via MapKit's
   `UserAnnotation()`, alongside the pets.
2. **"Find Pet"** (`Features/Find`): a full-screen compass arrow that always
   points toward the pet's last known position, with the distance shown
   below it, the same interaction model as Find My's proximity view (minus
   Ultra-Wideband precision finding, which needs dedicated U1-chip hardware
   neither the phone's Bluetooth trackers nor Traccar provide).

The distance and bearing math (haversine distance, initial great-circle
bearing) lives in `LibrePawKit` as plain functions on `Coordinate`, no
CoreLocation dependency there, consistent with ADR-0005. Only the *app*
layer touches `CoreLocation`, to read the device's own position/heading.

Devices (and the Simulator) without a magnetometer report
`CLLocationManager.headingAvailable() == false`; in that case the arrow
points using the raw bearing from true north instead of a heading-corrected
one, and the UI shows a small disclosure label explaining this.

## Consequences

- `Info.plist` now declares `NSLocationWhenInUseUsageDescription`.
- Location updates only run while the Map tab or a Find Pet screen is
  actually visible (`.task`/`.onDisappear` start/stop the manager), no
  background location, no "Always" authorization, keeping the privacy
  footprint as small as the feature allows.
- If the user denies access, the Map tab simply shows no "you are here" dot,
  and Find Pet shows a dedicated screen explaining why and linking to
  Settings, the rest of the app is unaffected.
- Compass accuracy (and therefore arrow accuracy) depends on the device's
  magnetometer and on-screen calibration; this is an inherent limitation of
  heading-based finding versus UWB precision finding, not something the app
  can work around.
