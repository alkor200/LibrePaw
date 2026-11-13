import SwiftUI
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import CoreLocation
import LibrePawKit

struct PetMapView: View {
    let petRepository: PetRepository
    let locationService: LocationService
    @State private var viewModel: PetMapViewModel
    @State private var camera: MapViewCamera = .default()
    /// A snapshot of `PetAnnotationView` per pet (photo included), fed to
    /// `SymbolStyleLayer` as a per-feature icon. Populated by the
    /// `.task(id:)` below, keyed on every pet's ``PinRenderKey`` so a pet
    /// that only gets its first position after this view has already
    /// appeared still gets rendered (a plain `.task` without `id:` only
    /// ever runs once, against whatever `petsWithPosition` was at first
    /// appearance, confirmed live: with a `.task` plain, a pet whose
    /// position arrived after mount kept the fallback icon forever).
    @State private var pinImages: [Int: UIImage] = [:]
    /// What each of `pinImages` was rendered from. A pin is re-rendered
    /// whenever its pet's key changes, not just rendered once per pet id,
    /// otherwise the status ring stayed whatever color it first had (an
    /// offline pet kept its green ring) and a newly saved photo never
    /// showed up on the map.
    @State private var pinRenderKeys: [Int: PinRenderKey] = [:]
    /// Bumped every time the map disappears, so the next appearance
    /// re-fetches every photo. Needed because Traccar always names an
    /// uploaded photo "device.jpg" (see `PetAnnotationView.overrideImage`),
    /// so a photo changed on another screen leaves `photoURL` untouched.
    @State private var photoGeneration = 0
    /// Which pet's long-press asked for a navigation app chooser; `nil`
    /// dismisses the dialog.
    @State private var navigationChoicePet: Pet?
    @Environment(AppTabNavigation.self) private var tabNavigation
    @Environment(\.colorScheme) private var colorScheme

    private static let petLayerID = "pet-pins"
    private static let fallbackPinImage = UIImage(systemName: "pawprint.circle.fill")!
        .withTintColor(.gray, renderingMode: .alwaysOriginal)

    init(petRepository: PetRepository, locationService: LocationService) {
        self.petRepository = petRepository
        self.locationService = locationService
        _viewModel = State(initialValue: PetMapViewModel(petRepository: petRepository))
    }

    var body: some View {
        GeometryReader { geometry in
            mapContent(bottomSafeArea: geometry.safeAreaInsets.bottom)
        }
        .ignoresSafeArea()
    }

    /// `bottomSafeArea` is the tab bar's own reported safe-area inset (read
    /// via `GeometryReader` rather than a guessed flat constant), used to
    /// place MapLibre's own ornament row (logo, attribution) flush just
    /// above the tab bar, and the locate button stacked above that, per
    /// the layout asked for live: "direkt ueber die liquid glass bubble und
    /// darueber dann das locate symbol".
    private func mapContent(bottomSafeArea: CGFloat) -> some View {
        // A single source of truth for "how far up MapLibre's own ornament
        // row sits", so the locate button's own clearance (below) is always
        // defined relative to this exact number, rather than two
        // independently-computed paddings that could drift apart on a
        // device whose actual safe-area/tab-bar geometry doesn't match
        // what was tested in the simulator (confirmed live: it did drift,
        // the button ended up level with, not above, the ornament row).
        let ornamentBottomInset = bottomSafeArea + 8
        return MapView(styleURL: OpenFreeMapStyle.url(for: colorScheme), camera: $camera) {
            // The whole layer only added once there's at least one pet, and
            // `mappings` below always has at least one entry whenever it
            // is: an empty `mappings` dictionary crashes MapLibre's style
            // engine outright ("Expected at least 4 arguments, but found
            // only 2", confirmed live) rather than just matching nothing,
            // which it otherwise would on every very first render, before
            // `pinImages` has anything in it yet (`renderPinImage(for:)`
            // is async). `effectivePinImages` papers over that gap with
            // the fallback icon per pet until the real photo is ready.
            if !viewModel.petsWithPosition.isEmpty {
                let petSource = ShapeSource(identifier: "pets") {
                    for pet in viewModel.petsWithPosition {
                        if let position = pet.lastPosition {
                            MLNPointFeature(coordinate: position.coordinate.clLocationCoordinate2D) { feature in
                                feature.attributes["petId"] = pet.id
                            }
                        }
                    }
                }

                let effectivePinImages = Dictionary(uniqueKeysWithValues: viewModel.petsWithPosition.map { pet in
                    (AnyHashable(pet.id), pinImages[pet.id] ?? Self.fallbackPinImage)
                })

                SymbolStyleLayer(identifier: Self.petLayerID, source: petSource)
                    .iconImage(featurePropertyNamed: "petId", mappings: effectivePinImages, default: Self.fallbackPinImage)
                    .iconAllowsOverlap(true)
            }
        }
        // Pushes MapLibre's own built-in ornaments (logo, attribution,
        // compass) up to sit flush just above the tab bar, using the real
        // device safe-area inset (from the enclosing `GeometryReader`, see
        // `body`) rather than a guessed flat constant, which still looked
        // "weirdly" placed on a device whose tab bar/home-indicator inset
        // didn't match the simulator's.
        .mapContentInset(UIEdgeInsets(top: 0, left: 0, bottom: ornamentBottomInset, right: 0))
        // `showsUserLocation` has no DSL-level modifier yet (see
        // `unsafeMapViewControllerModifier`'s own doc comment, which gives
        // this exact example), unlike the MapKit version's `UserAnnotation()`.
        .unsafeMapViewControllerModifier { controller in
            controller.mapView.showsUserLocation = true
        }
        // Limitation: unlike the MapKit version's `.contextMenu`
        // (anchored right over the pressed pin), MapLibreSwiftUI's
        // `onLongPressMapGesture` only gives a coordinate, no built-in
        // feature hit-testing for long press (`onTapMapGesture(on:)` has
        // that, long press doesn't). Approximated here by nearest pet
        // within a small radius rather than true hit-testing, and
        // presented as a confirmationDialog (always a bottom sheet on
        // iPhone, see the fix earlier this session for why that's not
        // anchored either way).
        .onTapMapGesture(on: [Self.petLayerID]) { _, features in
            guard let petId = features.first?.attributes["petId"] as? Int,
                  let pet = viewModel.petsWithPosition.first(where: { $0.id == petId }) else { return }
            tabNavigation.showPetDetail(pet)
        }
        .onLongPressMapGesture { context in
            guard let pet = nearestPet(to: Coordinate(context.coordinate)) else { return }
            if !NavigationApp.openIfOnlyOneInstalled(for: pet) {
                navigationChoicePet = pet
            }
        }
        .confirmationDialog(
            "Navigate to \(navigationChoicePet?.name ?? "")",
            isPresented: Binding(
                get: { navigationChoicePet != nil },
                set: { if !$0 { navigationChoicePet = nil } }
            ),
            titleVisibility: .visible,
            presenting: navigationChoicePet
        ) { pet in
            ForEach(NavigationApp.installed) { app in
                Button(app.label) {
                    app.openDirections(to: pet)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                locationService.requestAuthorizationIfNeeded()
                if let coordinate = locationService.coordinate?.clLocationCoordinate2D {
                    withAnimation {
                        camera = .center(coordinate, zoom: 16)
                    }
                }
            } label: {
                Image(systemName: "location.fill")
                    .mapControlButtonStyle()
            }
            .padding()
            // Defined relative to `ornamentBottomInset`, not independently,
            // so it's always clearly above the ornament row regardless of
            // the device. Confirmed live on-device: +50 wasn't enough
            // clearance, doubled to +100.
            .padding(.bottom, ornamentBottomInset + 120)
        }
        // No title: it's the tab's own root screen, already labeled by the
        // tab bar itself, a floating "Map" label only got in the way of a
        // full-bleed map underneath it.
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: tabNavigation.mapFocusPet) { _, pet in
            guard let pet, let coordinate = pet.lastPosition?.coordinate.clLocationCoordinate2D else { return }
            withAnimation {
                camera = .center(coordinate, zoom: 16)
            }
            tabNavigation.mapFocusPet = nil
        }
        .onChange(of: viewModel.petsWithPosition.map(\.id)) {
            fitCameraToAllPets()
        }
        .task(id: viewModel.petsWithPosition.map { PinRenderRequest(petID: $0.id, key: pinRenderKey(for: $0)) }) {
            for pet in viewModel.petsWithPosition {
                let key = pinRenderKey(for: pet)
                guard pinRenderKeys[pet.id] != key else { continue }
                let image = await renderPinImage(for: pet)
                // A cancelled photo fetch renders without the photo, don't
                // let that replace a good pin or mark this key as done.
                guard !Task.isCancelled else { return }
                pinImages[pet.id] = image
                pinRenderKeys[pet.id] = key
            }
        }
        .overlay(alignment: .top) {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .safeAreaPadding(.top)
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
        .task {
            viewModel.startLiveUpdates()
            locationService.requestAuthorizationIfNeeded()
            locationService.startUpdating()
        }
        .onDisappear {
            viewModel.stopLiveUpdates()
            locationService.stopUpdating()
            photoGeneration += 1
        }
    }

    private struct PinRenderKey: Hashable {
        let status: Pet.Status
        let photoURL: URL?
        let photoGeneration: Int
    }

    private struct PinRenderRequest: Hashable {
        let petID: Int
        let key: PinRenderKey
    }

    private func pinRenderKey(for pet: Pet) -> PinRenderKey {
        PinRenderKey(status: pet.status, photoURL: pet.photoURL, photoGeneration: photoGeneration)
    }

    /// Renders a snapshot of `PetAnnotationView` (fetching the photo once,
    /// up front, via `overrideImage` rather than letting the view's own
    /// `.task` fetch it, since `ImageRenderer.uiImage` is read synchronously
    /// right after construction and wouldn't wait for that).
    private func renderPinImage(for pet: Pet) async -> UIImage {
        let photoData = try? await petRepository.fetchPhoto(for: pet)
        let photo = photoData.flatMap { UIImage(data: $0) }
        // `ImageRenderer` captures exactly `PetAnnotationView`'s own frame
        // (its `size` parameter), with no room for its `.shadow(radius:)`
        // to render into, so without this padding the shadow got hard
        // clipped at the circle's edge (confirmed live: a visibly
        // pixelated, cut-off ring around the pin).
        let renderer = ImageRenderer(content: PetAnnotationView(pet: pet, petRepository: petRepository, overrideImage: photo).padding(6))
        renderer.scale = await UIScreen.main.scale
        renderer.isOpaque = false
        return renderer.uiImage ?? Self.fallbackPinImage
    }

    /// Long press only gives a coordinate (see the comment on
    /// `onLongPressMapGesture` above), approximated here as "the nearest
    /// pet, if close enough to plausibly be the one pressed".
    private func nearestPet(to coordinate: Coordinate, maximumDistanceMeters: Double = 50) -> Pet? {
        viewModel.petsWithPosition
            .compactMap { pet -> (Pet, Double)? in
                guard let position = pet.lastPosition else { return nil }
                return (pet, coordinate.distanceMeters(to: position.coordinate))
            }
            .filter { $0.1 <= maximumDistanceMeters }
            .min { $0.1 < $1.1 }
            .map(\.0)
    }

    private func fitCameraToAllPets() {
        let coordinates = viewModel.petsWithPosition.compactMap { $0.lastPosition?.coordinate.clLocationCoordinate2D }
        guard !coordinates.isEmpty else { return }
        // A single coordinate is a zero-size bounding box, a degenerate case
        // for `.showcase()`'s fit-bounds math (confirmed live: with only one
        // pet, the map got stuck requesting tiles forever and never
        // rendered anything past the initial background color). Centering
        // on it directly, the same way the locate button and
        // `tabNavigation.mapFocusPet` already do, sidesteps that entirely.
        guard coordinates.count > 1 else {
            withAnimation {
                camera = .center(coordinates[0], zoom: 16)
            }
            return
        }
        let shapeCollection = MLNShapeCollection(shapes: [MLNPointCollectionFeature(coordinates: coordinates, count: UInt(coordinates.count))])
        withAnimation {
            camera = .showcase(shapeCollection: shapeCollection, edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 80, right: 40))
        }
    }
}
