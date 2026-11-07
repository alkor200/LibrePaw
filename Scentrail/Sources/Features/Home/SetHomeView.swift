import SwiftUI
import MapKit
import ScentrailKit

/// Lets an owner mark their current location (plus a radius) as a pet's
/// "home", which powers excursion detection (see ADR-0014). Deliberately
/// has no draggable map pin — "current location + a radius" was the whole
/// ask, and it keeps the flow to a single screen with no map gestures.
struct SetHomeView: View {
    @State private var viewModel: SetHomeViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SetHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                preview
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Scentrail will use your current location as \(viewModel.pet.name)'s home.")
            }

            Section("Radius") {
                Slider(value: $viewModel.radiusMeters, in: 20...500, step: 10)
                Text("\(Int(viewModel.radiusMeters)) meters")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let existingHome = viewModel.existingHome {
                Section {
                    Label(
                        "Home is already set (radius \(Int(existingHome.radiusMeters))m). Saving will move it to your current location.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
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
                            Text("Save Home Here")
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.locationService.coordinate == nil || viewModel.isSaving)
            }
        }
        .navigationTitle("Set Home")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.locationService.requestAuthorizationIfNeeded()
            viewModel.locationService.startUpdating()
            await viewModel.loadExistingHome()
        }
        .onDisappear {
            viewModel.locationService.stopUpdating()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let coordinate = viewModel.locationService.coordinate?.clLocationCoordinate2D {
            Map(initialPosition: .region(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: viewModel.radiusMeters * 4, longitudinalMeters: viewModel.radiusMeters * 4)
            )) {
                MapCircle(center: coordinate, radius: viewModel.radiusMeters)
                    .foregroundStyle(.tint.opacity(0.2))
                    .stroke(.tint, lineWidth: 2)
                Marker("Home", systemImage: "house.fill", coordinate: coordinate)
            }
            .allowsHitTesting(false)
        } else {
            ProgressView("Finding your location…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    NavigationStack {
        SetHomeView(viewModel: SetHomeViewModel(pet: .previewOnline, petRepository: PreviewPetRepository(), locationService: LocationService()))
    }
}
