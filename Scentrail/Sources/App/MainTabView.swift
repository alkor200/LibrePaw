import SwiftUI
import ScentrailKit

/// The authenticated app's root UI: a native tab bar with Pets, Map, and
/// Settings, each in its own navigation stack.
struct MainTabView: View {
    let session: StoredSession
    let petRepository: PetRepository
    let onLogOut: () -> Void

    var body: some View {
        TabView {
            NavigationStack {
                PetListView(petRepository: petRepository)
            }
            .tabItem {
                Label("Pets", systemImage: "pawprint.fill")
            }

            NavigationStack {
                PetMapView(petRepository: petRepository)
            }
            .tabItem {
                Label("Map", systemImage: "map.fill")
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
