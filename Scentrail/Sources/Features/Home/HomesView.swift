import SwiftUI
import ScentrailKit

/// Lists a pet's home geofences (see ADR-0016) — tap one to move/rename it,
/// swipe to delete, or add a new one. Replaces the single-home `SetHomeView`
/// as the destination from `PetDetailView`; `SetHomeView` itself is now
/// reached from here, either to add or to edit one specific home.
struct HomesView: View {
    let petRepository: PetRepository
    let locationService: LocationService
    @State private var viewModel: HomesViewModel
    @State private var isAddingHome = false

    init(viewModel: HomesViewModel, petRepository: PetRepository, locationService: LocationService) {
        _viewModel = State(initialValue: viewModel)
        self.petRepository = petRepository
        self.locationService = locationService
    }

    var body: some View {
        content
            .navigationTitle("\(viewModel.pet.name)'s Homes")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeGeofence.self) { home in
                SetHomeView(viewModel: SetHomeViewModel(pet: viewModel.pet, existingHome: home, petRepository: petRepository, locationService: locationService))
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingHome = true
                    } label: {
                        Label("Add Home", systemImage: "plus")
                    }
                }
            }
            // `onDismiss` rather than relying on `.onAppear` alone: verified
            // live that `.onAppear` does *not* reliably re-fire when a sheet
            // dismisses over the presenting view the way it does when a
            // pushed destination pops (the edit path below) — without this,
            // a newly added home was saved correctly server-side but never
            // showed up in the list until the next unrelated reload.
            .sheet(isPresented: $isAddingHome, onDismiss: { Task { await viewModel.load() } }) {
                NavigationStack {
                    SetHomeView(viewModel: SetHomeViewModel(pet: viewModel.pet, existingHome: nil, petRepository: petRepository, locationService: locationService))
                }
            }
            // `.onAppear` rather than `.task`: this view stays mounted (just
            // covered) while editing a home pushes `SetHomeView` on top of
            // it — reloading here picks up whatever was just saved once the
            // owner pops back, the same way it does after returning from
            // `HomeGeofence`'s navigationDestination above.
            .onAppear { Task { await viewModel.load() } }
            .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Couldn't Load Homes", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
            }
        } else if viewModel.homes.isEmpty {
            ContentUnavailableView {
                Label("No Homes Yet", systemImage: "house")
            } description: {
                Text("Add \(viewModel.pet.name)'s first home to start seeing excursions.")
            } actions: {
                Button("Add Home") { isAddingHome = true }
            }
        } else {
            List {
                ForEach(viewModel.homes) { home in
                    NavigationLink(value: home) {
                        HomeRow(home: home)
                    }
                }
                .onDelete { offsets in
                    let homesToDelete = offsets.map { viewModel.homes[$0] }
                    Task {
                        for home in homesToDelete {
                            await viewModel.delete(home)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct HomeRow: View {
    let home: HomeGeofence

    var body: some View {
        HStack {
            Image(systemName: "house.fill")
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(home.name)
                    .font(.headline)
                Text("\(Int(home.radiusMeters)) m radius")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        HomesView(
            viewModel: HomesViewModel(pet: .previewOnline, petRepository: PreviewPetRepository()),
            petRepository: PreviewPetRepository(),
            locationService: LocationService()
        )
    }
}
