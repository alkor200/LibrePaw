import SwiftUI
import MapKit
import ScentrailKit

/// Today's recorded trail on its own screen, reached from the pet detail
/// page's actions card. Reads straight from `PetDetailViewModel`, which
/// already loads today's trail for the "Distance Today" stat tile — no
/// separate fetch needed here.
struct TodaysTrailView: View {
    let viewModel: PetDetailViewModel
    let petRepository: PetRepository
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                mapCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today's Trail")
        .navigationBarTitleDisplayMode(.inline)
        .task { fitCameraToTrail() }
        .onChange(of: viewModel.trail) { fitCameraToTrail() }
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Map(position: $cameraPosition) {
                if let position = viewModel.pet.lastPosition {
                    Annotation(viewModel.pet.name, coordinate: position.coordinate.clLocationCoordinate2D) {
                        PetAnnotationView(pet: viewModel.pet, petRepository: petRepository, size: 32)
                    }
                }
                if viewModel.trail.count > 1 {
                    MapPolyline(coordinates: viewModel.trail.map(\.coordinate.clLocationCoordinate2D))
                        .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if viewModel.isLoadingTrail {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let trailErrorMessage = viewModel.trailErrorMessage {
                Label(trailErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if viewModel.trail.count <= 1 {
                Text("No movement recorded yet today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func fitCameraToTrail() {
        var coordinates = viewModel.trail.map(\.coordinate.clLocationCoordinate2D)
        if let last = viewModel.pet.lastPosition?.coordinate.clLocationCoordinate2D {
            coordinates.append(last)
        }
        guard let region = MKCoordinateRegion.fitting(coordinates) else { return }
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
