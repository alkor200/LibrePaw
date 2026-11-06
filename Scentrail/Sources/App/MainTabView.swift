import SwiftUI
import ScentrailKit

/// The authenticated app's root UI: a native tab bar with Pets, Map, and
/// Settings, each in its own navigation stack.
struct MainTabView: View {
    let session: StoredSession
    let petRepository: PetRepository
    let locationService: LocationService
    let onLogOut: () -> Void

    var body: some View {
        // Map is listed first so it's the default tab on launch.
        TabView {
            NavigationStack {
                PetMapView(petRepository: petRepository, locationService: locationService)
            }
            .tabItem {
                Label("Map", systemImage: "map.fill")
            }

            NavigationStack {
                PetListView(petRepository: petRepository, locationService: locationService)
            }
            .tabItem {
                Label("Pets", systemImage: "pawprint.fill")
            }

            NavigationStack {
                SettingsView(session: session, onLogOut: onLogOut)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }
}
