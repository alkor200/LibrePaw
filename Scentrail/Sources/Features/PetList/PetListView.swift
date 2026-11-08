import SwiftUI
import ScentrailKit

struct PetListView: View {
    let petRepository: PetRepository
    let locationService: LocationService
    @State private var viewModel: PetListViewModel

    init(petRepository: PetRepository, locationService: LocationService) {
        self.petRepository = petRepository
        self.locationService = locationService
        _viewModel = State(initialValue: PetListViewModel(petRepository: petRepository))
    }

    var body: some View {
        content
            .background(Color.appBackground)
            .navigationTitle("Pets")
            .navigationDestination(for: Pet.self) { pet in
                PetDetailView(
                    viewModel: PetDetailViewModel(pet: pet, petRepository: petRepository),
                    petRepository: petRepository,
                    locationService: locationService
                )
            }
            .task { viewModel.startLiveUpdates() }
            .onDisappear { viewModel.stopLiveUpdates() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading pets…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Pets", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await viewModel.refresh() } }
            }

        case .loaded(let pets) where pets.isEmpty:
            ContentUnavailableView {
                Label("No Pets Yet", systemImage: "pawprint")
            } description: {
                Text("Pets you add as devices in Traccar will show up here.")
            }

        case .loaded(let pets):
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 20)], spacing: 24) {
                    ForEach(pets) { pet in
                        NavigationLink(value: pet) {
                            PetGridCell(pet: pet, petRepository: petRepository)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .refreshable { await viewModel.refresh() }
        }
    }
}

#Preview {
    NavigationStack {
        PetListView(petRepository: PreviewPetRepository(), locationService: LocationService())
    }
}
