import SwiftUI
import LibrePawKit

/// Lists a pet's home geofences (see ADR-0016), tap one to move/rename it,
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
            .background(Color.appBackground)
            .navigationTitle("\(viewModel.pet.name)'s Homes")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeGeofence.self) { home in
                SetHomeView(viewModel: SetHomeViewModel(pet: viewModel.pet, existingHome: home, petRepository: petRepository, locationService: locationService))
            }
            .toolbar {
                if viewModel.canManageHomes {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAddingHome = true
                        } label: {
                            Label("Add Home", systemImage: "plus")
                        }
                    }
                }
            }
            // `onDismiss` rather than relying on `.onAppear` alone: verified
            // live that `.onAppear` does *not* reliably re-fire when a sheet
            // dismisses over the presenting view the way it does when a
            // pushed destination pops (the edit path below), without this,
            // a newly added home was saved correctly server-side but never
            // showed up in the list until the next unrelated reload.
            .sheet(isPresented: $isAddingHome, onDismiss: { Task { await viewModel.load() } }) {
                NavigationStack {
                    SetHomeView(viewModel: SetHomeViewModel(pet: viewModel.pet, existingHome: nil, petRepository: petRepository, locationService: locationService))
                }
            }
            // `.onAppear` rather than `.task`: this view stays mounted (just
            // covered) while editing a home pushes `SetHomeView` on top of
            // it, reloading here picks up whatever was just saved once the
            // owner pops back, the same way it does after returning from
            // `HomeGeofence`'s navigationDestination above.
            .onAppear { Task { await viewModel.load() } }
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.loadPermissionContext() }
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
                Text(viewModel.canManageHomes
                    ? "Add \(viewModel.pet.name)'s first home to start seeing excursions."
                    : "\(viewModel.pet.name) has no homes set up yet.")
            } actions: {
                if viewModel.canManageHomes {
                    Button("Add Home") { isAddingHome = true }
                }
            }
            .safeAreaInset(edge: .top) { visibilityNotice }
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
                .deleteDisabled(!viewModel.canManageHomes)
                .listRowBackground(Color.appSurface)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top) { visibilityNotice }
        }
    }

    /// Explains who can actually see, and do anything with, what's set up
    /// here: visibility follows admin status (the one thing ADR-0019 asks
    /// for in exchange for showing this screen to everyone), while whether
    /// the account can add/edit/delete at all follows Traccar's own
    /// `readonly` flag (see ADR-0023). Shown only once ``HomesViewModel/permissions``
    /// is known, so it never flashes the wrong wording while loading.
    @ViewBuilder
    private var visibilityNotice: some View {
        if let permissions = viewModel.permissions {
            if permissions.isAdministrator {
                visibilityNoticeLabel("As an admin, homes you add here are visible to everyone with access to \(viewModel.pet.name).", systemImage: "person.3.fill")
            } else if !permissions.canManageHomes {
                visibilityNoticeLabel("You have read-only access to this account. You can see homes here, but can't add, edit, or delete them.", systemImage: "lock.fill")
            } else {
                visibilityNoticeLabel("Homes you add here, and the excursions they create, are only visible to you. Ask an admin to add a home if it should apply to everyone.", systemImage: "eye.slash.fill")
            }
        }
    }

    private func visibilityNoticeLabel(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .foregroundStyle(.appSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
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
                    .foregroundStyle(.appSecondaryText)
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
