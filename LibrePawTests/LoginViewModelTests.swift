import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("LoginViewModel")
@MainActor
struct LoginViewModelTests {
    @Test("canSubmit is false until server, email and password are all filled in")
    func canSubmitRequiresAllFields() {
        let viewModel = makeViewModel()
        #expect(viewModel.canSubmit == false)

        viewModel.serverURLString = "traccar.example.com"
        viewModel.email = "owner@example.com"
        #expect(viewModel.canSubmit == false)

        viewModel.password = "secret"
        #expect(viewModel.canSubmit == true)
    }

    @Test("canSubmit is false for an http address even with all fields filled in")
    func canSubmitRejectsInsecureConnection() {
        let viewModel = makeViewModel()
        viewModel.serverURLString = "http://traccar.example.com"
        viewModel.email = "owner@example.com"
        viewModel.password = "secret"

        #expect(viewModel.canSubmit == false)
    }

    @Test("usesInsecureConnection flags http addresses but not https")
    func flagsInsecureConnections() {
        let viewModel = makeViewModel()

        viewModel.serverURLString = "http://traccar.example.com"
        #expect(viewModel.usesInsecureConnection == true)

        viewModel.serverURLString = "https://traccar.example.com"
        #expect(viewModel.usesInsecureConnection == false)
    }

    @Test("A successful login authenticates the app session")
    func successfulLoginAuthenticatesSession() async {
        let appSession = AppSession(authenticationService: FakeAuthenticationService())
        let viewModel = LoginViewModel(appSession: appSession)
        viewModel.serverURLString = "traccar.example.com"
        viewModel.email = "owner@example.com"
        viewModel.password = "secret"

        await viewModel.logIn()

        #expect(viewModel.errorMessage == nil)
        #expect(appSession.isAuthenticated == true)
    }

    @Test("A failed login surfaces an error and leaves the session unauthenticated")
    func failedLoginSurfacesError() async {
        let authenticationService = FakeAuthenticationService(loginResult: .failure(LibrePawError.invalidCredentials))
        let appSession = AppSession(authenticationService: authenticationService)
        let viewModel = LoginViewModel(appSession: appSession)
        viewModel.serverURLString = "traccar.example.com"
        viewModel.email = "owner@example.com"
        viewModel.password = "wrong-password"

        await viewModel.logIn()

        #expect(viewModel.errorMessage != nil)
        #expect(appSession.isAuthenticated == false)
    }

    @Test("Submitting (e.g. Return in the password field) does nothing while canSubmit is false")
    func logInRespectsCanSubmit() async {
        let appSession = AppSession(authenticationService: FakeAuthenticationService())
        let viewModel = LoginViewModel(appSession: appSession)
        viewModel.serverURLString = "http://traccar.example.com"
        viewModel.email = "owner@example.com"
        viewModel.password = "secret"

        await viewModel.logIn()
        #expect(appSession.isAuthenticated == false)

        viewModel.serverURLString = "traccar.example.com"
        viewModel.email = "   "
        await viewModel.logIn()
        #expect(appSession.isAuthenticated == false)
    }

    @Test("Only https server addresses are accepted, with or without a port")
    func onlyHTTPSIsAccepted() async {
        for (address, accepted) in [
            ("ftp://traccar.example.com", false),
            ("ws://traccar.example.com", false),
            ("https://traccar.example.com:8443", true),
            ("HTTPS://traccar.example.com", true)
        ] {
            let appSession = AppSession(authenticationService: FakeAuthenticationService())
            let viewModel = LoginViewModel(appSession: appSession)
            viewModel.serverURLString = address
            viewModel.email = "owner@example.com"
            viewModel.password = "secret"

            await viewModel.logIn()

            #expect(appSession.isAuthenticated == accepted, "\(address)")
            #expect((viewModel.errorMessage != nil) == !accepted, "\(address)")
        }
    }

    private func makeViewModel() -> LoginViewModel {
        LoginViewModel(appSession: AppSession(authenticationService: FakeAuthenticationService()))
    }
}
