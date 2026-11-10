import SwiftUI
import UIKit
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import LibrePawKit

/// Shows a pet's current home (if any) and lets the owner move it, the pin
/// stays fixed at the center of the screen while the map pans underneath it,
/// the same interaction Apple Maps and Maps-based pickers use for "drop a
/// pin here", rather than being limited to the owner's own current location
/// (see ADR-0014 for why home matters: it drives excursion detection).
struct SetHomeView: View {
    @State private var viewModel: SetHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var camera: MapViewCamera
    @State private var hasCenteredCamera: Bool

    init(viewModel: SetHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
        // When editing an existing home, `viewModel.homeCoordinate` is
        // already set at init time (unlike adding a new one, where it only
        // becomes available later via `.task`/`.onChange` below), so
        // `content` takes the `homeCoordinate != nil` branch on its very
        // first render. Seeding `camera` with its final position here,
        // rather than leaving it at `.default()` and jumping it a moment
        // later in `.task`, matters a lot more than it looks: the MapKit
        // version of this screen hit a real re-initialization spiral from
        // mounting at one position and immediately redirecting (see
        // ADR-0016), and while unconfirmed whether MapLibre has the same
        // failure mode, avoiding the same mount-then-jump pattern here
        // costs nothing and sidesteps the question entirely.
        if let coordinate = viewModel.homeCoordinate {
            _camera = State(initialValue: .center(coordinate.clLocationCoordinate2D, zoom: Self.zoomLevel(forRadiusMeters: viewModel.radiusMeters, atLatitude: coordinate.latitude)))
            _hasCenteredCamera = State(initialValue: true)
        } else {
            _camera = State(initialValue: .default())
            _hasCenteredCamera = State(initialValue: false)
        }
    }

    var body: some View {
        content
            .background(Color.appBackground)
            .navigationTitle(viewModel.isEditingExistingHome ? Text("Edit Home") : Text("Add Home"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isEditingExistingHome, viewModel.canManage == true {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            viewModel.requestDelete()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(viewModel.isDeleting)
                    }
                }
            }
            .confirmationDialog(
                "Delete \(viewModel.name)?",
                isPresented: Binding(
                    get: { viewModel.isShowingDeleteConfirmation },
                    set: { isPresented in if !isPresented { viewModel.cancelDelete() } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.confirmDelete()
                        if viewModel.didDelete { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            }
            .task {
                viewModel.locationService.requestAuthorizationIfNeeded()
                viewModel.locationService.startUpdating()
                viewModel.useCurrentLocationIfUnset()
                centerCameraIfNeeded()
            }
            .task { await viewModel.loadPermissionContext() }
            .onChange(of: viewModel.locationService.coordinate) {
                viewModel.useCurrentLocationIfUnset()
                centerCameraIfNeeded()
            }
            .onDisappear {
                viewModel.locationService.stopUpdating()
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.locationService.isDenied, viewModel.homeCoordinate == nil {
            deniedView
        } else if let homeCoordinate = viewModel.homeCoordinate {
            ZStack {
                MapView(styleURL: OpenFreeMapStyle.url(for: colorScheme), camera: $camera) {
                    // A real polygon approximating a circle, not
                    // `MapCircle`/`CircleStyleLayer`: MapLibre's circle
                    // radius is in screen pixels, not meters, so it
                    // wouldn't stay the true geofence size across zoom
                    // levels the way this needs to (see
                    // `Coordinate.circlePolygon(radiusMeters:)`'s doc
                    // comment).
                    let circleSource = ShapeSource(identifier: "home-circle") {
                        let ring = homeCoordinate.circlePolygon(radiusMeters: viewModel.radiusMeters).map(\.clLocationCoordinate2D)
                        MLNPolygonFeature(coordinates: ring, count: UInt(ring.count))
                    }
                    FillStyleLayer(identifier: "home-circle-fill", source: circleSource)
                        .fillColor(UIColor(Color.appPrimary))
                        .fillOpacity(0.2)
                    LineStyleLayer(identifier: "home-circle-outline", source: circleSource)
                        .lineColor(UIColor(Color.appPrimaryDark))
                        .lineWidth(2)
                }
                .onChange(of: camera) { _, newCamera in
                    guard viewModel.canManage != false, case let .centered(onCoordinate: coordinate, _, _, _, _) = newCamera.state else { return }
                    viewModel.homeCoordinate = Coordinate(coordinate)
                }

                Image(systemName: "house.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.tint, in: Circle())
                    .shadow(radius: 3)
                    .offset(y: -16)
                    .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom) { controlsCard }
        } else {
            ProgressView("Finding your location…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var controlsCard: some View {
        VStack(spacing: 16) {
            TextField("Name", text: $viewModel.name)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.canManage == false)

            Text("Drag the map to place \(viewModel.name.trimmed.isEmpty ? localized("it") : viewModel.name).")
                .font(.footnote)
                .foregroundStyle(.appSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Slider(value: $viewModel.radiusMeters, in: 20...100, step: 5)
                    .disabled(viewModel.canManage == false)
                Text("\(Int(viewModel.radiusMeters)) meters radius")
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
            }

            visibilityNotice

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "xmark.octagon.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Hidden rather than shown-disabled when `canManage == false`:
            // there's nothing the signed-in account can do here at all, see
            // ADR-0021's "hide rather than offer a broken affordance"
            // reasoning (same one ADR-0018 already established for
            // Share `<Pet>`).
            if viewModel.canManage != false {
                Button {
                    Task {
                        await viewModel.save()
                        if viewModel.didSave { dismiss() }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            viewModel.isEditingExistingHome ? Text("Save") : Text("Add Home")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isSaving || viewModel.canManage != true)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    /// Same visibility explanation as `HomesView`'s, inline here too since
    /// this is the actual point of action, see ADR-0019 and ADR-0023.
    @ViewBuilder
    private var visibilityNotice: some View {
        if let permissions = viewModel.permissions {
            if permissions.isAdministrator {
                noticeLabel("Visible to everyone with access to \(viewModel.pet.name).", systemImage: "person.3.fill")
            } else if !permissions.canManageHomes {
                noticeLabel("You have read-only access to this account. You can view this, but not edit or delete it.", systemImage: "lock.fill")
            } else {
                noticeLabel("Only visible to you. Ask an admin to add this if it should apply to everyone.", systemImage: "eye.slash.fill")
            }
        }
    }

    private func noticeLabel(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .foregroundStyle(.appSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Location Access Needed", systemImage: "location.slash")
        } description: {
            Text("LibrePaw needs your location to suggest a starting point for \(viewModel.pet.name)'s home.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func centerCameraIfNeeded() {
        guard !hasCenteredCamera, let coordinate = viewModel.homeCoordinate else { return }
        hasCenteredCamera = true
        camera = .center(coordinate.clLocationCoordinate2D, zoom: Self.zoomLevel(forRadiusMeters: viewModel.radiusMeters, atLatitude: coordinate.latitude))
    }

    /// MapLibre's camera is a zoom level, not an explicit meter span the way
    /// `MKCoordinateRegion` is. Solves the standard web-mercator "meters per
    /// point at a given zoom/latitude" formula for the zoom that fits
    /// `radiusMeters * 6` (same multiple the MapKit version used) across an
    /// assumed ~350pt-wide screen.
    private static func zoomLevel(forRadiusMeters radiusMeters: Double, atLatitude latitude: Double) -> Double {
        let desiredSpanMeters = radiusMeters * 6
        let assumedScreenWidthPoints = 350.0
        let metersPerPointAtZoom0 = 156_543.03392 * cos(latitude * .pi / 180)
        return log2(metersPerPointAtZoom0 * assumedScreenWidthPoints / desiredSpanMeters)
    }
}

#Preview {
    NavigationStack {
        SetHomeView(viewModel: SetHomeViewModel(pet: .previewOnline, existingHome: nil, petRepository: PreviewPetRepository(), locationService: LocationService()))
    }
}
