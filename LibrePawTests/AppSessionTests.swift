import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("AppSession")
@MainActor
struct AppSessionTests {
    private let serverURL = URL(string: "https://traccar.example.com")!

    @Test("Rejected credentials end the session and remember it for the login screen")
    func rejectedCredentialsEndSession() async throws {
        let appSession = AppSession(authenticationService: FakeAuthenticationService())
        try await appSession.logIn(serverURL: serverURL, email: "owner@example.com", password: "old")
        let session = try #require(appSession.session)

        appSession.handleRejectedCredentials(for: session)

        #expect(appSession.isAuthenticated == false)
        #expect(appSession.petRepository == nil)
        #expect(appSession.expiredSession == session)

        let loginViewModel = LoginViewModel(appSession: appSession)
        #expect(loginViewModel.email == "owner@example.com")
        #expect(loginViewModel.serverURLString == serverURL.absoluteString)
        #expect(loginViewModel.errorMessage != nil)
    }

    @Test("A rejection reported for an older session doesn't end a newer one")
    func staleRejectionIsIgnored() async throws {
        let appSession = AppSession(authenticationService: FakeAuthenticationService())
        try await appSession.logIn(serverURL: serverURL, email: "first@example.com", password: "x")
        let firstSession = try #require(appSession.session)
        appSession.logOut()
        try await appSession.logIn(serverURL: serverURL, email: "second@example.com", password: "y")

        appSession.handleRejectedCredentials(for: firstSession)

        #expect(appSession.session?.email == "second@example.com")
        #expect(appSession.expiredSession == nil)
    }

    @Test("An ordinary logout doesn't pre-fill or explain anything on the login screen")
    func ordinaryLogoutHasNoNotice() async throws {
        let appSession = AppSession(authenticationService: FakeAuthenticationService())
        try await appSession.logIn(serverURL: serverURL, email: "owner@example.com", password: "x")

        appSession.logOut()

        #expect(appSession.expiredSession == nil)
        #expect(LoginViewModel(appSession: appSession).errorMessage == nil)
    }

    @Test("The session's repository reports invalidCredentials and passes the error through")
    func repositoryReportsInvalidCredentials() async {
        let reported = Reported()
        let repository = SessionExpiryDetectingPetRepository(base: FakePetRepository(error: LibrePawError.invalidCredentials)) {
            reported.mark()
        }

        await #expect(throws: LibrePawError.invalidCredentials) {
            try await repository.fetchPets()
        }
        #expect(reported.value)
    }

    @Test("Any other error is passed through without being reported")
    func otherErrorsAreNotReported() async {
        let reported = Reported()
        let repository = SessionExpiryDetectingPetRepository(base: FakePetRepository(error: LibrePawError.forbidden)) {
            reported.mark()
        }

        await #expect(throws: LibrePawError.forbidden) {
            try await repository.fetchPets()
        }
        #expect(!reported.value)
    }
}

private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false
    var value: Bool { lock.withLock { marked } }
    func mark() { lock.withLock { marked = true } }
}
