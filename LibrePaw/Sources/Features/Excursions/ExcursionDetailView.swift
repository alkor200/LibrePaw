import SwiftUI
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import LibrePawKit

struct ExcursionDetailView: View {
    @State private var viewModel: ExcursionDetailViewModel
    @State private var camera: MapViewCamera = .default()
    @Environment(\.colorScheme) private var colorScheme

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
        .navigationTitle(Formatting.date(viewModel.excursion.startTime))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadTrail()
            fitCameraToTrail()
        }
    }

    private var header: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            statTile(systemImage: "flag.fill", title: "Started", value: Formatting.time(viewModel.excursion.startTime))

            if viewModel.excursion.isOngoing {
                statTile(systemImage: "hare.fill", title: "Status", value: localized("Away now"))
            } else if let endTime = viewModel.excursion.endTime {
                statTile(systemImage: "flag.checkered", title: "Ended", value: Formatting.time(endTime))
            }

            if let distance = viewModel.excursion.distanceMeters {
                statTile(systemImage: "map.fill", title: "Distance", value: Formatting.distance(distance))
            }

            if let duration = viewModel.excursion.duration {
                statTile(systemImage: "clock", title: "Duration", value: Formatting.duration(duration))
            }

            if let averageSpeedKmh = viewModel.excursion.averageSpeedKilometersPerHour {
                statTile(systemImage: "gauge.with.dots.needle.67percent", title: "Avg. Speed", value: Formatting.speed(averageSpeedKmh, fractionDigits: 1))
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

    private func statTile(systemImage: String, title: LocalizedStringKey, value: String) -> some View {
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

            MapView(styleURL: OpenFreeMapStyle.url(for: colorScheme), camera: $camera) {
                if viewModel.trail.count > 1 {
                    let routeSource = ShapeSource(identifier: "excursion-route") {
                        MLNPolylineFeature(coordinates: viewModel.trail.map(\.coordinate.clLocationCoordinate2D))
                    }
                    LineStyleLayer(identifier: "excursion-route", source: routeSource)
                        .lineCap(.round)
                        .lineJoin(.round)
                        .lineColor(UIColor(Color.appPrimaryDark))
                        .lineWidth(4)
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
        guard let fitted = MapViewCamera.fitting(coordinates, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)) else { return }
        withAnimation {
            camera = fitted
        }
    }
}

#if DEBUG
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
#endif
