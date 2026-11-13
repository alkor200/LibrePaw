import SwiftUI
import LibrePawKit

@main
struct LibrePawApp: App {
    private let dependencies = AppDependencies.live()

    init() {
        // Has to run before any view renders and reads a localized string,
        // see ADR-0022.
        AppLanguageStore.applyStoredOverride()

        #if DEBUG
        // UI tests start from a signed-out app regardless of what this
        // simulator's Keychain still holds: Keychain items survive
        // reinstalling the app, so a simulator that was ever signed in
        // would otherwise restore that session and never show the login
        // screen the tests expect.
        if ProcessInfo.processInfo.arguments.contains(Self.resetStateLaunchArgument) {
            try? LiveAuthenticationService().logOut()
        }
        #endif
    }

    #if DEBUG
    static let resetStateLaunchArgument = "-UITestResetState"
    #endif

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
