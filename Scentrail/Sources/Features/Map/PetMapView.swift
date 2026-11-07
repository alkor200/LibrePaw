import SwiftUI
import MapKit
import ScentrailKit

struct PetMapView: View {
    let petRepository: PetRepository
    let locationService: LocationService
    @State private var viewModel: PetMapViewModel
    @State private var cameraPosition: MapCameraPosition
    @State private var selectedPet: Pet?
    @State private var mapLayer: MapLayer = .standard

    /// - Parameter initialFocus: when provided (e.g. opened from a pet's
    ///   detail screen via "View on Map"), the camera starts centered on
    ///   that pet's last known position instead of fitting all pets.
    init(petRepository: PetRepository, locationService: LocationService, initialFocus: Pet? = nil) {
        self.petRepository = petRepository
        self.locationService = locationService
        _viewModel = State(initialValue: PetMapViewModel(petRepository: petRepository))
        if let coordinate = initialFocus?.lastPosition?.coordinate.clLocationCoordinate2D {
            _cameraPosition = State(initialValue: .region(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            ))
        } else {
            _cameraPosition = State(initialValue: .automatic)
        }
    }

    var body: some View {
        Map(position: $cameraPosition, selection: $selectedPet) {
            UserAnnotation()

            ForEach(viewModel.petsWithPosition) { pet in
                if let position = pet.lastPosition {
                    Annotation(pet.name, coordinate: position.coordinate.clLocationCoordinate2D) {
                        PetAnnotationView(pet: pet, petRepository: petRepository)
                    }
                    .tag(pet)
                }
            }
        }
        .mapStyle(mapLayer.mapStyle)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .overlay(alignment: .bottomLeading) {
            MapLayerPicker(selection: $mapLayer)
                .padding()
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPet) { pet in
            PetDetailView(
                viewModel: PetDetailViewModel(pet: pet, petRepository: petRepository),
                petRepository: petRepository,
                locationService: locationService
            )
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
