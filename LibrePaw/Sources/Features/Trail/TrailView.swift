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
    private static let lineLayerIDPrefix = "trail-line-"
    private static let lineHitLayerIDPrefix = "trail-line-hit-"
    private static let midpointLayerIDPrefix = "trail-midpoint-"

    var body: some View {
        MapView(styleURL: OpenFreeMapStyle.url(for: colorScheme), camera: $camera) {
            let routes = Array(viewModel.excursions.enumerated()).compactMap { index, excursion -> (excursion: Excursion, positions: [PetPosition], color: UIColor)? in
                guard let positions = viewModel.trailsByExcursionID[excursion.id], positions.count > 1 else { return nil }
                return (excursion, positions, color(at: index))
            }

            for route in routes {
                // Carries the same excursionId attribute as the midpoint feature below, so a tap
                // anywhere on the route itself (not just the small midpoint dot) can look up which
                // excursion it belongs to, see onTapMapGesture below.
                let polyline = MLNPolylineFeature(coordinates: route.positions.map(\.coordinate.clLocationCoordinate2D))
                polyline.attributes["excursionId"] = route.excursion.id
                let lineSource = ShapeSource(identifier: "\(Self.lineLayerIDPrefix)\(route.excursion.id)") {
                    polyline
                }
                // An invisible, much wider line sharing the same source, purely so the route is
                // actually tappable: MapLibre's tap hit-test checks the exact pixel under a finger
                // against a layer's own rendered stroke width, and the visible 4pt line is far too
                // thin to reliably land a tap on (confirmed live, 2026-11-13, see
                // onTapMapGesture below, which hit-tests this layer instead of the visible one).
                LineStyleLayer(identifier: "\(Self.lineHitLayerIDPrefix)\(route.excursion.id)", source: lineSource)
                    .lineWidth(30)
                    .lineOpacity(0)
                LineStyleLayer(identifier: "\(Self.lineLayerIDPrefix)\(route.excursion.id)", source: lineSource)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(route.color)
                    .lineWidth(4)
            }

            // A SymbolStyleLayer with a rendered dot image, not a CircleStyleLayer: this app's own
            // tappable pet pins on PetMapView already use SymbolStyleLayer successfully, and
            // CircleStyleLayer turned out not to be hit-testable by onTapMapGesture(on:) at all in
            // this MapLibre version (confirmed live, 2026-11-13: the midpoint dot never opened its
            // excursion, on either layer type the line itself was tried with too). One layer per
            // excursion rather than one shared one with per-feature iconImage mapping, simplest way
            // to keep each excursion's own route color without a mappings dictionary.
            for route in routes {
                let midpointSource = ShapeSource(identifier: "\(Self.midpointLayerIDPrefix)\(route.excursion.id)") {
                    MLNPointFeature(coordinate: route.positions[route.positions.count / 2].coordinate.clLocationCoordinate2D) { feature in
                        feature.attributes["excursionId"] = route.excursion.id
                    }
                }
                SymbolStyleLayer(identifier: "\(Self.midpointLayerIDPrefix)\(route.excursion.id)", source: midpointSource)
                    .iconImage(Self.dotImage(color: route.color))
                    .iconAllowsOverlap(true)
            }
        }
        // `on: nil` ("check every layer"), not a Set built from viewModel.excursions: MapLibreSwiftUI's
        // onTapMapGesture(on:) only ever registers once, in ScopedGestureView's .onAppear, with
        // whatever Set the "on:" parameter evaluated to at that first render (confirmed live,
        // 2026-11-13: it never re-registers on a later body re-evaluation, even though this view's
        // own body constructs a fresh Set from viewModel.excursions on every one). Since excursions
        // loads asynchronously, that first Set was always empty, and every tap, on the route, the
        // midpoint dot, or anything else, ever since has hit-tested against zero layers. A plain
        // `nil` sidesteps the whole lifecycle bug by being the same unchanging value on every render,
        // exactly like PetMapView's own tap gesture already does with its constant petLayerID.
        .onTapMapGesture(on: nil) { _, features in
            // `features.first` isn't safe here the way it was with a scoped layer Set: `nil` means
            // MapLibre hit-tests every rendered layer, including the base map's own roads/labels/etc,
            // so the array can contain several unrelated features ahead of ours depending on z-order.
            guard let excursionId = features.first(where: { $0.attributes["excursionId"] != nil })?.attributes["excursionId"] as? Int,
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

    /// A filled circle with a white stroke, matching the old CircleStyleLayer's own
    /// `.radius(8).strokeWidth(2).strokeColor(.white)` look, now rendered as a plain image for
    /// SymbolStyleLayer instead (see its doc comment above for why).
    private static func dotImage(color: UIColor, diameter: CGFloat = 20) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return renderer.image { _ in
            let strokeWidth: CGFloat = 2
            let rect = CGRect(x: strokeWidth / 2, y: strokeWidth / 2, width: diameter - strokeWidth, height: diameter - strokeWidth)
            let path = UIBezierPath(ovalIn: rect)
            color.setFill()
            path.fill()
            UIColor.white.setStroke()
            path.lineWidth = strokeWidth
            path.stroke()
        }
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
