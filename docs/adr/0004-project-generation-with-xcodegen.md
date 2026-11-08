# 4. Generate the Xcode project with XcodeGen

## Status

Accepted

## Context

A checked-in `.xcodeproj` is an opaque, XML-ish property list that multiple
contributors editing targets/files concurrently will reliably produce merge
conflicts in. This is a well-known pain point for open source iOS projects.

## Decision

The Xcode project is **generated, not committed**. [XcodeGen](https://github.com/yonaskolb/XcodeGen)
reads a single declarative `project.yml` at the repository root and produces
`Scentrail.xcodeproj`. The generated project is gitignored.

Contributors run:

```sh
brew install xcodegen   # once
xcodegen generate       # whenever project.yml changes, or after a fresh clone
```

before opening the project in Xcode.

## Consequences

- Adding/removing/moving source files does not require touching the
  `.xcodeproj` directly - XcodeGen uses folder references driven by
  `project.yml`'s `sources:` entries, so new files under an existing source
  directory are picked up automatically on the next `xcodegen generate`.
- Build settings, targets, and scheme configuration live in `project.yml`
  as readable, diffable YAML.
- CI must run `xcodegen generate` before building (see `.github/workflows/ci.yml`).
- Contributors need XcodeGen installed locally. This is documented in the
  README's "Getting Started" section.
