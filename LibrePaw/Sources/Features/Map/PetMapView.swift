import SwiftUI
import MapKit
import LibrePawKit

struct PetMapView: View {
    let petRepository: PetRepository
    let locationService: LocationService
    @State private var viewModel: PetMapViewModel
    @State private var cameraPosition: MapCameraPosition
    @State private var mapLayer: MapLayer = .standard
    /// Which pet's long-press context menu asked for a navigation app
    /// chooser; `nil` dismisses the dialog. Tracked per pet rather than a
    /// plain `Bool`, multiple pets can each trigger this independently.
    @State private var navigationChoicePet: Pet?
    @Environment(AppTabNavigation.self) private var tabNavigation

    init(petRepository: PetRepository, locationService: LocationService) {
        self.petRepository = petRepository
        self.locationService = locationService
        _viewModel = State(initialValue: PetMapViewModel(petRepository: petRepository))
        _cameraPosition = State(initialValue: .automatic)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
                .tint(.appPrimaryDark)

            ForEach(viewModel.petsWithPosition) { pet in
                if let position = pet.lastPosition {
                    Annotation(pet.name, coordinate: position.coordinate.clLocationCoordinate2D) {
                        // `.onTapGesture`/`.onLongPressGesture` directly,
                        // not a `Button`: a `Button` with a long-press
                        // gesture layered on top fires only the button's
                        // own tap on release, long- or short-press alike
                        // (confirmed live), this pairing is the standard
                        // conflict-free way to tell the two apart. Tap
                        // drives `tabNavigation` rather than Map's own
                        // `selection` binding plus
                        // `.navigationDestination(item:)`: that combination
                        // was fragile, the live position feed keeps
                        // reassigning `selection` to fresh `Pet` values as
                        // pets move, and tying navigation to that same
                        // binding let an unrelated re-render of this view
                        // re-resolve the destination while pet detail was
                        // already pushed, racing with navigation happening
                        // deeper in the stack and leaving pet detail's
                        // buttons unresponsive (and, eventually, this map
                        // unable to render at all). Tap switches to the
                        // Pets tab and pushes that pet's detail there,
                        // rather than pushing within this tab's own stack;
                        // long press goes straight to navigating, rather
                        // than surfacing a context menu with that as its
                        // only item, one less tap to get the same outcome.
                        PetAnnotationView(pet: pet, petRepository: petRepository)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tabNavigation.showPetDetail(pet)
                            }
                            .onLongPressGesture {
                                if !NavigationApp.openIfOnlyOneInstalled(for: pet) {
                                    navigationChoicePet = pet
                                }
                            }
                    }
                }
            }
        }
        .mapStyle(mapLayer.mapStyle)
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .topTrailing) {
            MapLayerPicker(selection: $mapLayer)
                .padding()
        }
        .overlay(alignment: .bottomTrailing) {
            // A custom button rather than `MapUserLocationButton`: that
            // control only ever draws itself when placed inside
            // `.mapControls`, which pins it to its own fixed corner
            // (confirmed live: moved into a plain `.overlay`, it still
            // occupies layout space but renders nothing). This one matches
            // its look via `mapControlButtonStyle()` instead.
            Button {
                locationService.requestAuthorizationIfNeeded()
                if let coordinate = locationService.coordinate?.clLocationCoordinate2D {
                    withAnimation {
                        cameraPosition = .region(
                            MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
                        )
                    }
                }
            } label: {
                Image(systemName: "location.fill")
                    .mapControlButtonStyle()
            }
            .padding()
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Navigate to \(navigationChoicePet?.name ?? "")",
            isPresented: Binding(
                get: { navigationChoicePet != nil },
                set: { if !$0 { navigationChoicePet = nil } }
            ),
            titleVisibility: .visible,
            presenting: navigationChoicePet
        ) { pet in
            ForEach(NavigationApp.installed) { app in
                Button(app.label) {
                    app.openDirections(to: pet)
                }
            }
        }
        .onChange(of: tabNavigation.mapFocusPet) { _, pet in
            // `PetMapView` is a single, long-lived instance (owned by
            // `MainTabView`), not re-created per visit, so the
            // `initialFocus` init parameter only ever applies once at
            // launch; this is what reacts to "View on Map"/the pet's photo
            // in Pet Detail afterward.
            guard let pet, let coordinate = pet.lastPosition?.coordinate.clLocationCoordinate2D else { return }
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
                )
            }
            tabNavigation.mapFocusPet = nil
        }
        .overlay(alignment: .top) {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .overlay {
            if viewModel.petsWithPosition.isEmpty, viewModel.errorMessage == nil {
                ContentUnavailableView(
                    "No Pet Locations Yet",
                    systemImage: "mappin.slash",
                    description: Text("Pets will appear here once their tracker reports a position.")
                )
            }
        }
        .task {
            viewModel.startLiveUpdates()
            locationService.requestAuthorizationIfNeeded()
            locationService.startUpdating()
        }
        .onDisappear {
            viewModel.stopLiveUpdates()
            locationService.stopUpdating()
        }
    }
}
