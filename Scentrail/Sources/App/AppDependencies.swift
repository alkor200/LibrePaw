import Foundation
import ScentrailKit

/// The app's top-level dependencies, constructed once in `ScentrailApp` and
/// passed down the view hierarchy explicitly (see ADR-0009).
@MainActor
struct AppDependencies {
    let authenticationService: AuthenticationService
    let locationService: LocationService

    static func live() -> AppDependencies {
        AppDependencies(authenticationService: LiveAuthenticationService(), locationService: LocationService())
    }

    #if DEBUG
    static func preview() -> AppDependencies {
        AppDependencies(authenticationService: PreviewAuthenticationService(), locationService: LocationService())
    }
    #endif
}
