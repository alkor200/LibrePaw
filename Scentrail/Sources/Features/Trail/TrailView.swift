import SwiftUI
import MapKit
import ScentrailKit

/// A full-screen map aggregating every excursion in an adjustable window
/// (default 24 hours), each drawn as its own colored route. Tapping a route
/// opens that excursion's detail screen, the same destination
/// `ExcursionsView`'s rows push to. Replaces the old single-day
/// `TodaysTrailView` (see ADR-0020).
struct TrailView: View {
    let petRepository: PetRepository
    @State private var viewModel: TrailViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic

    init(viewModel: TrailViewModel, petRepository: PetRepository) {
        _viewModel = State(initialValue: viewModel)
        self.petRepository = petRepository
    }

    /// Stable per-excursion colors: cycling a fixed, visually distinct
    /// palette by each excursion's position in `viewModel.excursions`
    /// (most-recent-first, same order every reload for a given window) so
    /// a route's color doesn't shuffle between renders.
    private static let palette: [Color] = [.blue, .orange, .purple, .pink, .teal, .indigo, .brown, .mint, .cyan, .yellow]

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(Array(viewModel.excursions.enumerated()), id: \.element.id) { index, excursion in
                if let positions = viewModel.trailsByExcursionID[excursion.id], positions.count > 1 {
                    let routeColor = color(at: index)

                    MapPolyline(coordinates: positions.map(\.coordinate.clLocationCoordinate2D))
                        .stroke(routeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                    // `MapPolyline` itself isn't a tappable target (confirmed
                    // live: a `selection`/`.tag()` binding on it never fires),
                    // so tapping "the route" is really tapping a marker
                    // dropped on it, the same `NavigationLink`-wrapped
                    // `Annotation` pattern `PetMapView` already uses for pet
                    // pins, placed at the route's midpoint fix.
                    Annotation(
                        excursion.startTime.formatted(date: .omitted, time: .shortened),
                        coordinate: positions[positions.count / 2].coordinate.clLocationCoordinate2D
                    ) {
                        NavigationLink(value: excursion) {
                            Circle()
                                .fill(routeColor)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(radius: 2)
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .navigationTitle("Trail")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            windowPicker
        }
        .overlay {
            if !viewModel.isLoading, viewModel.errorMessage == nil, viewModel.excursions.isEmpty {
                ContentUnavailableView(
                    "No Trail Yet",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    description: Text("\(viewModel.pet.name) hasn't been on an excursion in the last \(viewModel.window.label.lowercased()).")
                )
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't Load Trail", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await reload() } }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
        .navigationDestination(for: Excursion.self) { excursion in
            ExcursionDetailView(viewModel: ExcursionDetailViewModel(
                excursion: excursion,
                petID: viewModel.pet.id,
                petRepository: petRepository
            ))
        }
        .task(id: viewModel.window) {
            await reload()
        }
    }

    private var windowPicker: some View {
        Picker("Window", selection: $viewModel.window) {
            ForEach(TrailWindow.allCases) { window in
                Text(window.label).tag(window)
            }
        }
        .pickerStyle(.segmented)
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding()
    }

    private func color(at index: Int) -> Color {
        Self.palette[index % Self.palette.count]
    }

    private func reload() async {
        await viewModel.load()
        fitCameraToAllTrails()
    }

    private func fitCameraToAllTrails() {
        let coordinates = viewModel.trailsByExcursionID.values.flatMap { $0 }.map(\.coordinate.clLocationCoordinate2D)
        guard let region = MKCoordinateRegion.fitting(coordinates) else { return }
        withAnimation {
            cameraPosition = .region(region)
        }
    }
}

#Preview {
    NavigationStack {
        TrailView(
            viewModel: TrailViewModel(pet: .previewOnline, petRepository: PreviewPetRepository()),
            petRepository: PreviewPetRepository()
        )
    }
}
