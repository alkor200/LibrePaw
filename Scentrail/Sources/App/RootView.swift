import SwiftUI

/// Switches between the login flow and the authenticated app based on
/// ``AppSession``'s state.
struct RootView: View {
    @State private var appSession: AppSession
    private let locationService: LocationService

    init(dependencies: AppDependencies) {
        _appSession = State(initialValue: AppSession(authenticationService: dependencies.authenticationService))
        locationService = dependencies.locationService
    }

    var body: some View {
        Group {
            if appSession.isRestoringSession {
                ProgressView()
            } else if appSession.isAuthenticated,
                      let session = appSession.session,
                      let petRepository = appSession.petRepository {
                MainTabView(session: session, petRepository: petRepository, locationService: locationService, onLogOut: appSession.logOut)
            } else {
                LoginView(appSession: appSession)
            }
        }
        .task {
            appSession.restoreSessionIfAvailable()
        }
    }
}
