import SwiftUI
import MapKit
import ScentrailKit

/// Today's recorded trail on its own full-screen map, reached from the pet
/// detail page's actions card — styled like `PetMapView`. Reads straight
/// from `PetDetailViewModel`, which already loads today's trail for the
/// "Distance Today" stat tile, so no separate fetch is needed here.
struct TodaysTrailView: View {
    let viewModel: PetDetailViewModel
    let petRepository: PetRepository
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasFitCamera = false

    var body: some View {
        Map(position: $cameraPosition) {
            if let position = viewModel.pet.lastPosition {
                Annotation(viewModel.pet.name, coordinate: position.coordinate.clLocationCoordinate2D) {
                    PetAnnotationView(pet: viewModel.pet, petRepository: petRepository)
                }
            }
            if viewModel.trail.count > 1 {
                MapPolyline(coordinates: viewModel.trail.map(\.coordinate.clLocationCoordinate2D))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .navigationTitle("Today's Trail")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if viewModel.isLoadingTrail {
                ProgressView()
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
            } else if let trailErrorMessage = viewModel.trailErrorMessage {
                Label(trailErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .overlay {
            if !viewModel.isLoadingTrail, viewModel.trailErrorMessage == nil, viewModel.trail.count <= 1 {
                ContentUnavailableView(
                    "No Movement Yet",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    description: Text("\(viewModel.pet.name) hasn't moved yet today.")
                )
            }
        }
        .task { fitCameraIfNeeded() }
        .onChange(of: viewModel.trail) { fitCameraIfNeeded() }
    }

    private func fitCameraIfNeeded() {
        guard !hasFitCamera else { return }
        var coordinates = viewModel.trail.map(\.coordinate.clLocationCoordinate2D)
        if let last = viewModel.pet.lastPosition?.coordinate.clLocationCoordinate2D {
            coordinates.append(last)
        }
        guard let region = MKCoordinateRegion.fitting(coordinates) else { return }
        hasFitCamera = true
        withAnimation {
            cameraPosition = .region(region)
        }
    }
}

#Preview {
    NavigationStack {
        TodaysTrailView(
            viewModel: PetDetailViewModel(pet: .previewOnline, petRepository: PreviewPetRepository()),
            petRepository: PreviewPetRepository()
        )
    }
}
