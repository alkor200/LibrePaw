# 15. Per-developer signing config via a gitignored xcconfig file

## Status

Accepted - supersedes the `DEVELOPMENT_TEAM` approach in
[ADR-0004](0004-project-generation-with-xcodegen.md)'s implementation

## Context

`DEVELOPMENT_TEAM` is personal per developer and must not be hardcoded into
`project.yml`, which is shared and committed. The first attempt at this
used an environment variable placeholder:

```yaml
DEVELOPMENT_TEAM: ${DEVELOPMENT_TEAM}
```

This does not work well in practice: `xcodegen generate` substitutes the
variable **at generation time**, baking whatever the variable happened to
be (often empty, since shells don't persist exported variables between
sessions) directly into the regenerated `.xcodeproj`. Every regeneration -
including routine ones after pulling changes or editing `project.yml` -
silently wiped the signing team, forcing a trip back to Xcode's Signing &
Capabilities tab to reselect it.

## Decision

`DEVELOPMENT_TEAM` is no longer set in `project.yml` at all. Instead, the
`Scentrail` target references an external xcconfig file via XcodeGen's
`configFiles`:

```yaml
configFiles:
  Debug: Scentrail/Config/Local.xcconfig
  Release: Scentrail/Config/Local.xcconfig
```

`Scentrail/Config/Local.xcconfig` is gitignored and contains one line:

```
DEVELOPMENT_TEAM = <your team id>
```

A committed `Scentrail/Config/Local.xcconfig.example` documents the format
and how to find your team id. Each developer copies it once, on first
clone.

The key difference from the environment-variable approach: `xcodegen
generate` only writes a **reference** to this file path into the
`.xcodeproj` - it never reads or inlines the file's contents. Xcode itself
resolves `DEVELOPMENT_TEAM` from the file at build time. Regenerating the
project doesn't touch the file, so the team selection survives indefinitely
once set.

## Consequences

- One-time setup per clone (copy the `.example` file, fill in one line) -
  slightly more than the env var approach's (nonexistent) setup, but it
  only has to happen once rather than before every `xcodegen generate`.
- `Scentrail/Config/Local.xcconfig` must exist for the project to build with
  a team at all; without it, Xcode falls back to no team (same as today's
  behavior when the env var was unset), which is a clear, discoverable
  failure (a Signing error in Xcode) rather than a silent reset.
- This same pattern - a gitignored `.xcconfig` referenced via `configFiles`,
  with a committed `.example` template - is the standard place to add any
  other future per-developer or secret build setting (e.g. a personal API
  key), rather than reaching for environment variables again.
