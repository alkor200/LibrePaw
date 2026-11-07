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
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCenteredCamera = false

    init(viewModel: SetHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle("\(viewModel.pet.name)'s Home")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.locationService.requestAuthorizationIfNeeded()
                viewModel.locationService.startUpdating()
                await viewModel.loadExistingHome()
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
            Label(homeStatusText, systemImage: "house.fill")
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
                    await viewModel.saveHome()
                    if viewModel.didSave { dismiss() }
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Text("Save Home")
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

    private var homeStatusText: String {
        if let existingHome = viewModel.existingHome {
            "Home is set, radius \(Int(existingHome.radiusMeters)) m. Drag the map to move it."
        } else {
            "No home set yet for \(viewModel.pet.name). Drag the map to place it."
        }
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
        guard !hasCenteredCamera, let coordinate = viewModel.homeCoordinate?.clLocationCoordinate2D else { return }
        hasCenteredCamera = true
        cameraPosition = .region(
            MKCoordinateRegion(center: coordinate, latitudinalMeters: viewModel.radiusMeters * 6, longitudinalMeters: viewModel.radiusMeters * 6)
        )
    }
}

#Preview {
    NavigationStack {
        SetHomeView(viewModel: SetHomeViewModel(pet: .previewOnline, petRepository: PreviewPetRepository(), locationService: LocationService()))
    }
}
