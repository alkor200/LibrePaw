import SwiftUI
import LibrePawKit

/// The app's three top-level tabs.
enum AppTab: Hashable {
    case map
    case pets
    case settings
}

/// Cross-tab navigation, injected into the environment from `RootView` so a
/// view deep inside one tab's own `NavigationStack` (a pet annotation on the
/// map, "View on Map" in Pet Detail) can switch the selected tab and land on
/// the right screen there, instead of just pushing within its own tab's
/// stack and leaving the tab bar on the wrong tab.
@Observable
@MainActor
final class AppTabNavigation {
    var selectedTab: AppTab = .map

    /// The Pets tab's own navigation path. Type-erased rather than `[Pet]`:
    /// `PetDetailView` pushes its own `PetDetailRoute` values (Find, Trail,
    /// Excursions, Homes, Share) on top of a pushed `Pet`, and a strongly
    /// typed array path can only ever hold one element type, which broke
    /// all of those the moment anything but a `Pet` tried to push here
    /// (confirmed live). Setting this from outside the Pets tab (tapping a
    /// pet annotation on the map) pushes straight to that pet's detail
    /// screen, replacing whatever was already pushed there, the same way
    /// choosing a different pet from the list would.
    var petsPath = NavigationPath()

    /// Set to focus the Map tab's camera on a specific pet (Pet Detail's
    /// "View on Map"/photo). `PetMapView` is a single, long-lived instance
    /// owned by `MainTabView`, not re-created on each visit, so this is a
    /// one-shot signal it observes and clears once consumed, rather than a
    /// constructor parameter it could read once at init.
    var mapFocusPet: Pet?

    func showPetDetail(_ pet: Pet) {
        petsPath = NavigationPath([pet])
        selectedTab = .pets
    }

    func showPetOnMap(_ pet: Pet) {
        mapFocusPet = pet
        selectedTab = .map
    }
}
