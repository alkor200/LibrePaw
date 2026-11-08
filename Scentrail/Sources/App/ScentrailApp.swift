import SwiftUI

@main
struct ScentrailApp: App {
    private let dependencies = AppDependencies.live()

    init() {
        // Has to run before any view renders and reads a localized string,
        // see ADR-0022.
        AppLanguageStore.applyStoredOverride()
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
