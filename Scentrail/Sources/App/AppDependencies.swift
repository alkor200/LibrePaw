import Foundation
import ScentrailKit

/// The app's top-level dependencies, constructed once in `ScentrailApp` and
/// passed down the view hierarchy explicitly (see ADR-0009).
struct AppDependencies {
    let authenticationService: AuthenticationService

    static func live() -> AppDependencies {
        AppDependencies(authenticationService: LiveAuthenticationService())
    }

    #if DEBUG
    static func preview() -> AppDependencies {
        AppDependencies(authenticationService: PreviewAuthenticationService())
    }
    #endif
}
