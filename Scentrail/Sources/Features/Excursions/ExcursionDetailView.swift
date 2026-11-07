import SwiftUI
import MapKit
import ScentrailKit

struct ExcursionDetailView: View {
    @State private var viewModel: ExcursionDetailViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic

    init(viewModel: ExcursionDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                mapCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.excursion.startTime.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadTrail()
            fitCameraToTrail()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if viewModel.excursion.isOngoing {
                statTile(systemImage: "figure.walk.motion", title: "Status", value: "Away now")
            } else if let duration = viewModel.excursion.duration {
                statTile(systemImage: "clock", title: "Duration", value: durationText(duration))
            }
            if let distance = viewModel.excursion.distanceMeters {
                statTile(systemImage: "shoeprints.fill", title: "Distance", value: distanceText(distance))
            }
        }
    }

    private func statTile(systemImage: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Map(position: $cameraPosition) {
                if let start = viewModel.trail.first {
                    Marker("Left home", coordinate: start.coordinate.clLocationCoordinate2D)
                        .tint(.green)
                }
                if !viewModel.excursion.isOngoing, let end = viewModel.trail.last {
                    Marker("Back home", coordinate: end.coordinate.clLocationCoordinate2D)
                        .tint(.gray)
                }
                if viewModel.trail.count > 1 {
                    MapPolyline(coordinates: viewModel.trail.map(\.coordinate.clLocationCoordinate2D))
                        .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if viewModel.trail.count <= 1 {
                Text("No route recorded for this excursion.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func fitCameraToTrail() {
        let coordinates = viewModel.trail.map(\.coordinate.clLocationCoordinate2D)
        guard let region = MKCoordinateRegion.fitting(coordinates) else { return }
        withAnimation {
            cameraPosition = .region(region)
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func distanceText(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)
    }
}

#Preview {
    NavigationStack {
        ExcursionDetailView(viewModel: ExcursionDetailViewModel(
            excursion: Excursion(
                id: 1,
                startTime: .now.addingTimeInterval(-3600),
                endTime: .now.addingTimeInterval(-1800),
                startCoordinate: Coordinate(latitude: 52.5200, longitude: 13.4050),
                endCoordinate: Coordinate(latitude: 52.5200, longitude: 13.4050),
                distanceMeters: 1240
            ),
            petID: Pet.previewOnline.id,
            petRepository: PreviewPetRepository()
        ))
    }
}
