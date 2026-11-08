import SwiftUI
import UIKit
import MapKit
import ScentrailKit

/// Shows a pet's current home (if any) and lets the owner move it — the pin
/// stays fixed at the center of the screen while the map pans underneath it,
/// the same interaction Apple Maps and Maps-based pickers use for "drop a
/// pin here" — rather than being limited to the owner's own current location
/// (see ADR-0014 for why home matters: it drives excursion detection).
struct SetHomeView: View {
    @State private var viewModel: SetHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition
    @State private var hasCenteredCamera: Bool

    init(viewModel: SetHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
        // When editing an existing home, `viewModel.homeCoordinate` is
        // already set at init time (unlike adding a new one, where it only
        // becomes available later via `.task`/`.onChange` below) — so `Map`
        // takes the `homeCoordinate != nil` branch in `content` on its very
        // first render. Seeding `cameraPosition` with its final region here,
        // rather than leaving it at `.automatic` and jumping it to `.region`
        // a moment later in `.task`, matters a lot more than it looks:
        // without this, `Map` mounts once at `.automatic` and is then
        // immediately redirected, which — observed on the simulator, see
        // ADR-0016 — sent `MKMapView` into a repeated re-initialization
        // spiral (each pass paying its multi-second cold-start cost) that
        // pegged the main thread and made the app look hung/crashed. Mounting
        // already at the final region avoids that transition entirely.
        if let coordinate = viewModel.homeCoordinate {
            _cameraPosition = State(initialValue: .region(Self.region(center: coordinate, radiusMeters: viewModel.radiusMeters)))
            _hasCenteredCamera = State(initialValue: true)
        } else {
            _cameraPosition = State(initialValue: .automatic)
            _hasCenteredCamera = State(initialValue: false)
        }
    }

    var body: some View {
        content
            .navigationTitle(viewModel.isEditingExistingHome ? "Edit Home" : "Add Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isEditingExistingHome {
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
                Map(position: $cameraPosition) {
                    MapCircle(center: homeCoordinate.clLocationCoordinate2D, radius: viewModel.radiusMeters)
                        .foregroundStyle(.tint.opacity(0.2))
                        .stroke(.tint, lineWidth: 2)
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    viewModel.homeCoordinate = Coordinate(context.region.center)
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

            Text("Drag the map to place \(viewModel.name.trimmed.isEmpty ? "it" : viewModel.name).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Slider(value: $viewModel.radiusMeters, in: 20...100, step: 5)
                Text("\(Int(viewModel.radiusMeters)) meters radius")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "xmark.octagon.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
                        Text(viewModel.isEditingExistingHome ? "Save" : "Add Home")
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isSaving)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Location Access Needed", systemImage: "location.slash")
        } description: {
            Text("Scentrail needs your location to suggest a starting point for \(viewModel.pet.name)'s home.")
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
        cameraPosition = .region(Self.region(center: coordinate, radiusMeters: viewModel.radiusMeters))
    }

    private static func region(center: Coordinate, radiusMeters: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center.clLocationCoordinate2D,
            latitudinalMeters: radiusMeters * 6,
            longitudinalMeters: radiusMeters * 6
        )
    }
}

#Preview {
    NavigationStack {
        SetHomeView(viewModel: SetHomeViewModel(pet: .previewOnline, existingHome: nil, petRepository: PreviewPetRepository(), locationService: LocationService()))
    }
}
