import SwiftUI
import MapKit
import ScentrailKit

struct PetDetailView: View {
    let petRepository: PetRepository
    let locationService: LocationService
    @State private var viewModel: PetDetailViewModel
    @State private var cameraPosition: MapCameraPosition

    init(viewModel: PetDetailViewModel, petRepository: PetRepository, locationService: LocationService) {
        self.petRepository = petRepository
        self.locationService = locationService
        _viewModel = State(initialValue: viewModel)
        if let coordinate = viewModel.pet.lastPosition?.coordinate {
            _cameraPosition = State(initialValue: .region(
                MKCoordinateRegion(
                    center: coordinate.clLocationCoordinate2D,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
            ))
        } else {
            _cameraPosition = State(initialValue: .automatic)
        }
    }

    var body: some View {
        List {
            Section {
                map
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }

            if viewModel.pet.lastPosition != nil {
                Section {
                    NavigationLink {
                        FindPetView(viewModel: FindPetViewModel(pet: viewModel.pet, petRepository: petRepository, locationService: locationService))
                    } label: {
                        Label("Find \(viewModel.pet.name)", systemImage: "location.north.circle.fill")
                    }
                }
            }

            Section("Status") {
                LabeledContent("Status", value: viewModel.pet.status.label)
                if let lastSeenAt = viewModel.pet.lastSeenAt {
                    LabeledContent("Last Update", value: lastSeenAt.formatted(.relative(presentation: .named)))
                }
            }

            if let position = viewModel.pet.lastPosition {
                Section("Last Known Position") {
                    if let address = position.address, !address.isEmpty {
                        LabeledContent("Address", value: address)
                    }
                    LabeledContent("Speed", value: formattedSpeed(position.speedKilometersPerHour))
                    if let battery = position.batteryLevelPercent {
                        LabeledContent("Battery", value: formattedPercent(battery))
                    }
                }
            }

            if viewModel.isLoadingTrail {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let trailErrorMessage = viewModel.trailErrorMessage {
                Section {
                    Label(trailErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(viewModel.pet.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadTodaysTrail() }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            if let position = viewModel.pet.lastPosition {
                Annotation(viewModel.pet.name, coordinate: position.coordinate.clLocationCoordinate2D) {
                    PetAnnotationView(pet: viewModel.pet, petRepository: petRepository)
                }
            }
            if viewModel.trail.count > 1 {
                MapPolyline(coordinates: viewModel.trail.map(\.coordinate.clLocationCoordinate2D))
                    .stroke(.tint, lineWidth: 3)
            }
        }
    }

    private func formattedSpeed(_ kilometersPerHour: Double) -> String {
        kilometersPerHour.formatted(.number.precision(.fractionLength(0))) + " km/h"
    }

    private func formattedPercent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }
}

#Preview {
    NavigationStack {
        PetDetailView(
            viewModel: PetDetailViewModel(pet: .previewOnline, petRepository: PreviewPetRepository()),
            petRepository: PreviewPetRepository(),
            locationService: LocationService()
        )
    }
}
