import Foundation
import LibrePawKit

/// Holds the app's authentication state for the current launch: whether a
/// session is restored/active, and the `PetRepository` scoped to it.
@Observable
@MainActor
final class AppSession {
    private(set) var session: StoredSession?
    private(set) var petRepository: PetRepository?
    private(set) var isRestoringSession = true
    /// The session most recently ended because the server stopped
    /// accepting its credentials, see ``handleRejectedCredentials(for:)``.
    /// Lets the login screen say why it's showing and pre-fill server and
    /// email. `nil` after an ordinary logout.
    private(set) var expiredSession: StoredSession?

    private let authenticationService: AuthenticationService

    init(authenticationService: AuthenticationService) {
        self.authenticationService = authenticationService
    }

    var isAuthenticated: Bool { session != nil }

    /// Loads a previously stored session, if any. Called once on launch.
    func restoreSessionIfAvailable() {
        defer { isRestoringSession = false }
        guard let restored = try? authenticationService.restoreSession() else { return }
        apply(restored)
    }

    func logIn(serverURL: URL, email: String, password: String) async throws {
        let session = try await authenticationService.logIn(serverURL: serverURL, email: email, password: password)
        apply(session)
    }

    func logOut() {
        expiredSession = nil
        // Clearing the Keychain item can fail transiently; retry once so a
        // momentary failure doesn't leave the credential behind even though
        // the UI (which can't stay around to report it, logging out
        // immediately switches back to the login screen) shows the user as
        // logged out either way.
        if (try? authenticationService.logOut()) == nil {
            try? authenticationService.logOut()
        }
        // Best-effort and not awaited, the UI switches back to the login
        // screen right away either way.
        if let petRepository {
            Task { await petRepository.endSession() }
        }
        session = nil
        petRepository = nil
    }

    /// Ends `session` because the server rejected its credentials, unless
    /// it already ended some other way (several requests failing at once
    /// all report this, and a stale request can finish after a new login).
    func handleRejectedCredentials(for session: StoredSession) {
        guard self.session == session else { return }
        logOut()
        expiredSession = session
    }

    private func apply(_ session: StoredSession) {
        expiredSession = nil
        self.session = session
        self.petRepository = SessionExpiryDetectingPetRepository(
            base: authenticationService.makePetRepository(for: session)
        ) { [weak self] in
            Task { @MainActor in self?.handleRejectedCredentials(for: session) }
        }
    }
}
