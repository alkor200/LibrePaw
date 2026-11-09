import SwiftUI
import LibrePawKit

/// The authenticated app's root UI: a native tab bar with Pets, Map, and
/// Settings, each in its own navigation stack.
struct MainTabView: View {
    let session: StoredSession
    let petRepository: PetRepository
    let locationService: LocationService
    let onLogOut: () -> Void
    @Environment(AppTabNavigation.self) private var tabNavigation

    var body: some View {
        @Bindable var tabNavigation = tabNavigation
        // Map is listed first so it's the default tab on launch.
        TabView(selection: $tabNavigation.selectedTab) {
            NavigationStack {
                PetMapView(petRepository: petRepository, locationService: locationService)
            }
            .tabItem {
                Label("Map", systemImage: "map.fill")
            }
            .tag(AppTab.map)

            NavigationStack(path: $tabNavigation.petsPath) {
                PetListView(petRepository: petRepository, locationService: locationService)
            }
            .tabItem {
                Label("Pets", systemImage: "pawprint.fill")
            }
            .tag(AppTab.pets)

            NavigationStack {
                SettingsView(session: session, onLogOut: onLogOut)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
    }
}
