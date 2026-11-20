import Foundation

/// Remembers the signed-in account's ``AccountPermissions`` for the rest of
/// the session, so only the first screen to ask has to wait for the server.
///
/// They come straight from Traccar's user flags and don't change while
/// signed in, but every Pet Detail, Homes and Set Home screen used to load
/// them again from scratch on each visit. Pet Detail inserts its Trail and
/// Excursions rows once they arrive, so each visit shifted the rows below
/// them a moment after the screen appeared, often right under the user's
/// finger, confirmed live: taps on Homes or Trail "did nothing" right after
/// opening Pet Detail, worst while a large excursion backfill held up the
/// request behind it.
///
/// Concurrent first callers share one request. A failure isn't remembered,
/// the next caller simply tries again.
actor AccountPermissionsCache {
    private var loading: Task<AccountPermissions, Error>?

    func value(loadingWith load: @escaping @Sendable () async throws -> AccountPermissions) async throws -> AccountPermissions {
        if let loading {
            return try await loading.value
        }
        let task = Task { try await load() }
        loading = task
        do {
            return try await task.value
        } catch {
            loading = nil
            throw error
        }
    }
}
