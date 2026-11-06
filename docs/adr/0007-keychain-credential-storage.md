# 7. Store server credentials in the Keychain

## Status

Accepted

## Context

Because authentication is per-request HTTP Basic Auth (see
[0006](0006-http-basic-auth-and-rest-polling.md)), the app must retain the
user's Traccar server URL, email and password across launches to stay
logged in. Passwords must never be stored in `UserDefaults` (unencrypted
plist, trivially readable on a jailbroken device or from a backup).

## Decision

- The password is stored exclusively in the iOS **Keychain**
  (`kSecClassGenericPassword`), via a small first-party wrapper
  (`KeychainCredentialStore` in `ScentrailKit`), with no third-party
  dependency — the Keychain API surface we need (add/read/update/delete one
  generic password item) is small enough that a wrapper library would add a
  dependency for little benefit.
- The server URL and email are non-secret and are also stored in the
  Keychain alongside the password as one `Codable` struct (`StoredSession`),
  for simplicity and so that login/logout is a single atomic write/delete —
  avoiding a split source of truth between Keychain and `UserDefaults`.
- Logging out deletes the Keychain item. No credentials are cached anywhere
  else (no disk cache, no logging of request headers).

## Consequences

- No third-party Keychain wrapper dependency.
- `ScentrailKit` has a direct dependency on the `Security` framework, which
  is acceptable since `ScentrailKit` is the app-specific data layer (unlike
  `TraccarKit`, which has no storage concerns at all).
- Unit tests that exercise `KeychainCredentialStore` run against the real
  Keychain (available in the simulator), using a dedicated test-only service
  name so they cannot collide with the app's own stored session.
