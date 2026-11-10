import SwiftUI
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import CoreLocation
import LibrePawKit

/// A full-screen map aggregating every excursion in an adjustable window
/// (default 24 hours), each drawn as its own colored route. Tapping a route
/// opens that excursion's detail screen, the same destination
/// `ExcursionsView`'s rows push to. Replaces the old single-day
/// `TodaysTrailView` (see ADR-0020).
struct TrailView: View {
    let petRepository: PetRepository
    @State private var viewModel: TrailViewModel
    @State private var camera: MapViewCamera = .default()
    @State private var pendingPush: Excursion?
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: TrailViewModel, petRepository: PetRepository) {
        _viewModel = State(initialValue: viewModel)
        self.petRepository = petRepository
    }

    /// Stable per-excursion colors: cycling a fixed, visually distinct
    /// palette by each excursion's position in `viewModel.excursions`
    /// (most-recent-first, same order every reload for a given window) so
    /// a route's color doesn't shuffle between renders.
    private static let palette: [UIColor] = [.systemBlue, .systemOrange, .systemPurple, .systemPink, .systemTeal, .systemIndigo, .systemBrown, .systemMint, .systemCyan, .systemYellow]
    private static let midpointLayerIDPrefix = "trail-midpoint-"

    var body: some View {
        MapView(styleURL: OpenFreeMapStyle.url(for: colorScheme), camera: $camera) {
            let routes = Array(viewModel.excursions.enumerated()).compactMap { index, excursion -> (excursion: Excursion, positions: [PetPosition], color: UIColor)? in
                guard let positions = viewModel.trailsByExcursionID[excursion.id], positions.count > 1 else { return nil }
                return (excursion, positions, color(at: index))
            }

            for route in routes {
                let lineSource = ShapeSource(identifier: "trail-line-\(route.excursion.id)") {
                    MLNPolylineFeature(coordinates: route.positions.map(\.coordinate.clLocationCoordinate2D))
                }
                LineStyleLayer(identifier: "trail-line-\(route.excursion.id)", source: lineSource)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(route.color)
                    .lineWidth(4)
            }

            // One CircleStyleLayer per excursion rather than one shared one:
            // unlike `SymbolStyleLayer.iconImage`, `CircleStyleLayer.color`
            // has no per-feature/data-driven mapping overload in this DSL,
            // only a single flat `UIColor` for the whole layer.
            for route in routes {
                let midpointSource = ShapeSource(identifier: "trail-midpoint-\(route.excursion.id)") {
                    MLNPointFeature(coordinate: route.positions[route.positions.count / 2].coordinate.clLocationCoordinate2D) { feature in
                        feature.attributes["excursionId"] = route.excursion.id
                    }
                }
                CircleStyleLayer(identifier: "\(Self.midpointLayerIDPrefix)\(route.excursion.id)", source: midpointSource)
                    .radius(8)
                    .color(route.color)
                    .strokeWidth(2)
                    .strokeColor(.white)
            }
        }
        .onTapMapGesture(on: Set(viewModel.excursions.map { "\(Self.midpointLayerIDPrefix)\($0.id)" })) { _, features in
            guard let excursionId = features.first?.attributes["excursionId"] as? Int,
                  let excursion = viewModel.excursions.first(where: { $0.id == excursionId }) else { return }
            pendingPush = excursion
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
                    // Not `.window.label.lowercased()`: German capitalizes
                    // nouns mid-sentence ("24 Stunden"), lowercasing it
                    // would misspell the translation.
                    description: Text("\(viewModel.pet.name) hasn't been on an excursion in the last \(viewModel.window.label).")
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
        .navigationDestination(item: $pendingPush) { excursion in
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

    private func color(at index: Int) -> UIColor {
        Self.palette[index % Self.palette.count]
    }

    private func reload() async {
        await viewModel.load()
        fitCameraToAllTrails()
    }

    private func fitCameraToAllTrails() {
        let coordinates = viewModel.trailsByExcursionID.values.flatMap { $0 }.map(\.coordinate.clLocationCoordinate2D)
        guard !coordinates.isEmpty else { return }
        // A single-point `.showcase()` is a zero-size bounding box, which
        // stalled MapLibre's render loop entirely in `PetMapView` (see its
        // `fitCameraToAllPets()`), so the same single-point case is
        // centered on directly here too.
        guard coordinates.count > 1 else {
            withAnimation {
                camera = .center(coordinates[0], zoom: 16)
            }
            return
        }
        let shapeCollection = MLNShapeCollection(shapes: [MLNPointCollectionFeature(coordinates: coordinates, count: UInt(coordinates.count))])
        withAnimation {
            camera = .showcase(shapeCollection: shapeCollection, edgePadding: UIEdgeInsets(top: 100, left: 40, bottom: 60, right: 40))
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
