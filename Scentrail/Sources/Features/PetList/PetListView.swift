import SwiftUI
import ScentrailKit

struct PetListView: View {
    let petRepository: PetRepository
    @State private var viewModel: PetListViewModel

    init(petRepository: PetRepository) {
        self.petRepository = petRepository
        _viewModel = State(initialValue: PetListViewModel(petRepository: petRepository))
    }

    var body: some View {
        content
            .navigationTitle("Pets")
            .navigationDestination(for: Pet.self) { pet in
                PetDetailView(viewModel: PetDetailViewModel(pet: pet, petRepository: petRepository))
            }
            .task { viewModel.startPolling() }
            .onDisappear { viewModel.stopPolling() }
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
            List(pets) { pet in
                NavigationLink(value: pet) {
                    PetRowView(pet: pet)
                }
            }
            .listStyle(.plain)
            .refreshable { await viewModel.refresh() }
        }
    }
}

#Preview {
    NavigationStack {
        PetListView(petRepository: PreviewPetRepository())
    }
}
