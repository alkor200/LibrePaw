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
        VStack(spacing: 12) {
            if viewModel.excursion.isLikelyVehicleTrip {
                vehicleTripBanner
            }
            if let routeText = viewModel.routeText {
                routeBanner(routeText)
            }
            header
            mapCard
        }
        .padding()
        .background(Color.appBackground)
        .navigationTitle(viewModel.excursion.startTime.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadTrail()
            fitCameraToTrail()
        }
    }

    private var header: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
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

            if let averageSpeedKmh = viewModel.excursion.averageSpeedKilometersPerHour {
                statTile(systemImage: "gauge.with.dots.needle.67percent", title: "Avg. Speed", value: speedText(averageSpeedKmh))
            }
        }
    }

    private var vehicleTripBanner: some View {
        Label("This looks like a car or train ride, it isn't counted in your totals.", systemImage: "car.fill")
            .font(.footnote)
            .foregroundStyle(.appSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func routeBanner(_ text: String) -> some View {
        Label(text, systemImage: "arrow.triangle.swap")
            .font(.footnote)
            .foregroundStyle(.appSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statTile(systemImage: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(.tint)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.appSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Takes whatever vertical space the stat tiles above leave over, so the
    /// whole screen, stats and route, fits without scrolling.
    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.subheadline.bold())
                .foregroundStyle(.appSecondaryText)

            Map(position: $cameraPosition) {
                if viewModel.trail.count > 1 {
                    MapPolyline(coordinates: viewModel.trail.map(\.coordinate.clLocationCoordinate2D))
                        .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .foregroundStyle(.appSecondaryText)
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
        .background(.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                endCoordinate: Coordinate(latitude: 52.4100, longitude: 13.0500),
                distanceMeters: 1240,
                startHomeID: 1,
                endHomeID: 2
            ),
            petID: Pet.previewOnline.id,
            petRepository: PreviewPetRepository()
        ))
    }
}
