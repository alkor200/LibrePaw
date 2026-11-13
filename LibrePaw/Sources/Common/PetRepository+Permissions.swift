import Foundation
import LibrePawKit

extension PetRepository {
    /// ``PetRepository/currentUserPermissions()``, retried a few times
    /// with growing delays (1s, 2s, 4s by default) before giving up and
    /// returning `nil`.
    ///
    /// Every screen gates its edit/share/add affordances on these
    /// permissions and treats them as best-effort, so a single dropped
    /// request used to hide those affordances (or leave Save disabled) for
    /// as long as the screen stayed open, with nothing ever trying again.
    /// Stops early when cancelled, or on `invalidCredentials`, which ends
    /// the session anyway.
    func currentUserPermissionsRetrying(attempts: Int = 4, initialDelay: Duration = .seconds(1)) async -> AccountPermissions? {
        var delay = initialDelay
        for attempt in 1...attempts {
            do {
                return try await currentUserPermissions()
            } catch LibrePawError.invalidCredentials {
                return nil
            } catch {
                guard attempt < attempts, !Task.isCancelled else { return nil }
                try? await Task.sleep(for: delay)
                delay *= 2
            }
        }
        return nil
    }
}
