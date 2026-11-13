import SwiftUI
import LibrePawKit

struct ExcursionsView: View {
    let petRepository: PetRepository
    @State private var viewModel: ExcursionsViewModel

    init(viewModel: ExcursionsViewModel, petRepository: PetRepository) {
        _viewModel = State(initialValue: viewModel)
        self.petRepository = petRepository
    }

    var body: some View {
        content
            .background(Color.appBackground)
            .navigationTitle("Excursions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Excursion.self) { excursion in
                ExcursionDetailView(viewModel: ExcursionDetailViewModel(
                    excursion: excursion,
                    petID: viewModel.pet.id,
                    petRepository: petRepository
                ))
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Couldn't Load Excursions", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
            }
        } else if viewModel.excursions.isEmpty {
            ContentUnavailableView {
                Label("No Excursions Yet", systemImage: "pawprint")
            } description: {
                Text("Once \(viewModel.pet.name) leaves home and comes back, excursions will show up here. Make sure a home location is set first.")
            }
        } else {
            List(viewModel.excursions) { excursion in
                NavigationLink(value: excursion) {
                    ExcursionRow(excursion: excursion, homeName: viewModel.homeName)
                }
                .listRowBackground(Color.appSurface)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct ExcursionRow: View {
    let excursion: Excursion
    /// Resolves a home geofence id (see `Excursion.startHomeID`/`endHomeID`)
    /// to the name the owner gave it, for the "Home → Cabin" route caption.
    let homeName: (Int?) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Formatting.dateTime(excursion.startTime))
                    .font(.headline)
                Spacer()
                if excursion.isOngoing {
                    Label("Away now", systemImage: "hare.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                } else if excursion.isLikelyVehicleTrip {
                    Label("Car ride?", systemImage: "car.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.appSecondaryText)
                }
            }

            if let routeText {
                Label(routeText, systemImage: "arrow.triangle.swap")
                    .font(.caption)
                    .foregroundStyle(.appSecondaryText)
            }

            HStack(spacing: 16) {
                if let duration = excursion.duration {
                    Label(Formatting.duration(duration), systemImage: "clock")
                }
                if let distance = excursion.distanceMeters {
                    Label(Formatting.distance(distance), systemImage: "map.fill")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.appSecondaryText)
        }
        .padding(.vertical, 4)
    }

    /// `nil` unless both ends resolve to a known home *and* they differ -
    /// an ordinary round trip to the same home says nothing new here.
    private var routeText: String? {
        guard let start = homeName(excursion.startHomeID), let end = homeName(excursion.endHomeID), start != end else { return nil }
        return "\(start) → \(end)"
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ExcursionsView(
            viewModel: ExcursionsViewModel(pet: .previewOnline, petRepository: PreviewPetRepository()),
            petRepository: PreviewPetRepository()
        )
    }
}
#endif
