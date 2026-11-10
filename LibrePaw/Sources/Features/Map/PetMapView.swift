import SwiftUI
import MapKit
import LibrePawKit

struct PetMapView: View {
    let petRepository: PetRepository
    let locationService: LocationService
    @State private var viewModel: PetMapViewModel
    @State private var cameraPosition: MapCameraPosition
    @State private var mapLayer: MapLayer = .standard
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
                        // A plain Button driving `tabNavigation`, rather
                        // than Map's own `selection` binding driving
                        // `.navigationDestination(item:)`. That combination
                        // was fragile: the live position feed keeps
                        // reassigning `selection` to fresh `Pet` values as
                        // pets move, and tying navigation to that same
                        // binding let an unrelated re-render of this view
                        // re-resolve the destination while pet detail was
                        // already pushed, racing with navigation happening
                        // deeper in the stack and leaving pet detail's
                        // buttons unresponsive (and, eventually, this map
                        // unable to render at all). This switches to the
                        // Pets tab and pushes that pet's detail there,
                        // rather than pushing within this tab's own stack.
                        Button {
                            tabNavigation.showPetDetail(pet)
                        } label: {
                            PetAnnotationView(pet: pet, petRepository: petRepository)
                        }
                        .contextMenu {
                            Button {
                                pet.openDirectionsInMaps()
                            } label: {
                                Label("Navigate to \(pet.name)", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
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
