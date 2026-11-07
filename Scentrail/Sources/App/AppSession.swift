import Foundation
import ScentrailKit

/// Holds the app's authentication state for the current launch: whether a
/// session is restored/active, and the `PetRepository` scoped to it.
@Observable
@MainActor
final class AppSession {
    private(set) var session: StoredSession?
    private(set) var petRepository: PetRepository?
    private(set) var isRestoringSession = true

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
        // Clearing the Keychain item can fail transiently; retry once so a
        // momentary failure doesn't leave the credential behind even though
        // the UI (which can't stay around to report it — logging out
        // immediately switches back to the login screen) shows the user as
        // logged out either way.
        if (try? authenticationService.logOut()) == nil {
            try? authenticationService.logOut()
        }
        session = nil
        petRepository = nil
    }

    private func apply(_ session: StoredSession) {
        self.session = session
        self.petRepository = authenticationService.makePetRepository(for: session)
    }
}
