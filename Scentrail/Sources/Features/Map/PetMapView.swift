import SwiftUI
import MapKit
import ScentrailKit

struct PetMapView: View {
    let petRepository: PetRepository
    @State private var viewModel: PetMapViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPet: Pet?

    init(petRepository: PetRepository) {
        self.petRepository = petRepository
        _viewModel = State(initialValue: PetMapViewModel(petRepository: petRepository))
    }

    var body: some View {
        Map(position: $cameraPosition, selection: $selectedPet) {
            ForEach(viewModel.petsWithPosition) { pet in
                if let position = pet.lastPosition {
                    Marker(pet.name, coordinate: position.coordinate.clLocationCoordinate2D)
                        .tint(pet.status == .online ? .green : .gray)
                        .tag(pet)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPet) { pet in
            PetDetailView(viewModel: PetDetailViewModel(pet: pet, petRepository: petRepository))
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
        .task { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
    }
}
