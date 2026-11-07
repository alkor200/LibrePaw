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
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(systemImage: "flag.fill", title: "Started", value: timeText(viewModel.excursion.startTime))

            if viewModel.excursion.isOngoing {
                statTile(systemImage: "figure.walk.motion", title: "Status", value: "Away now")
            } else if let endTime = viewModel.excursion.endTime {
                statTile(systemImage: "flag.checkered", title: "Ended", value: timeText(endTime))
            }

            if let distance = viewModel.excursion.distanceMeters {
                statTile(systemImage: "shoeprints.fill", title: "Distance", value: distanceText(distance))
            }

            if let duration = viewModel.excursion.duration {
                statTile(systemImage: "clock", title: "Duration", value: durationText(duration))
            }

            if let averageSpeedKmh {
                statTile(systemImage: "gauge.with.dots.needle.67percent", title: "Avg. Speed", value: speedText(averageSpeedKmh))
            }
        }
    }

    /// `nil` while the excursion is still ongoing — its duration isn't fixed
    /// yet, so an average over it wouldn't mean much.
    private var averageSpeedKmh: Double? {
        guard let distance = viewModel.excursion.distanceMeters,
              let duration = viewModel.excursion.duration,
              duration > 0 else { return nil }
        return (distance / duration) * 3.6
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

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func speedText(_ kilometersPerHour: Double) -> String {
        kilometersPerHour.formatted(.number.precision(.fractionLength(1))) + " km/h"
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
