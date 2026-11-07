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
        ScrollView {
            VStack(spacing: 20) {
                header
                trailMapCard
                if viewModel.pet.lastPosition != nil {
                    findButton
                }
                actionsCard
                statGrid
                locationRow
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.pet.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadTodaysTrail()
            fitCameraToTrail()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            PetAnnotationView(pet: viewModel.pet, petRepository: petRepository, size: 96)
            Text(viewModel.pet.name)
                .font(.title2.bold())
            Text(statusCaption)
                .font(.subheadline)
                .foregroundStyle(viewModel.pet.status.tintColor)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusCaption: String {
        switch viewModel.pet.status {
        case .online:
            "Online"
        case .offline, .unknown:
            if let lastSeenAt = viewModel.pet.lastSeenAt {
                "\(viewModel.pet.status.label) · \(lastSeenAt.formatted(.relative(presentation: .named)))"
            } else {
                viewModel.pet.status.label
            }
        }
    }

    // MARK: - Trail map

    private var trailMapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today's Trail", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Map(position: $cameraPosition) {
                if let position = viewModel.pet.lastPosition {
                    Annotation(viewModel.pet.name, coordinate: position.coordinate.clLocationCoordinate2D) {
                        PetAnnotationView(pet: viewModel.pet, petRepository: petRepository, size: 32)
                    }
                }
                if viewModel.trail.count > 1 {
                    MapPolyline(coordinates: viewModel.trail.map(\.coordinate.clLocationCoordinate2D))
                        .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if viewModel.isLoadingTrail {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let trailErrorMessage = viewModel.trailErrorMessage {
                Label(trailErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if viewModel.trail.count <= 1 {
                Text("No movement recorded yet today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func fitCameraToTrail() {
        var coordinates = viewModel.trail.map(\.coordinate.clLocationCoordinate2D)
        if let last = viewModel.pet.lastPosition?.coordinate.clLocationCoordinate2D {
            coordinates.append(last)
        }
        guard let region = MKCoordinateRegion.fitting(coordinates) else { return }
        withAnimation {
            cameraPosition = .region(region)
        }
    }

    // MARK: - Find button

    private var findButton: some View {
        NavigationLink {
            FindPetView(viewModel: FindPetViewModel(pet: viewModel.pet, petRepository: petRepository, locationService: locationService))
        } label: {
            Label("Find \(viewModel.pet.name)", systemImage: "location.north.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                PetMapView(petRepository: petRepository, locationService: locationService, initialFocus: viewModel.pet)
            } label: {
                actionRow(systemImage: "map.fill", title: "View on Map")
            }

            Divider().padding(.leading, 44)

            NavigationLink {
                ExcursionsView(
                    viewModel: ExcursionsViewModel(pet: viewModel.pet, petRepository: petRepository),
                    petRepository: petRepository
                )
            } label: {
                actionRow(systemImage: "figure.walk", title: "Excursions")
            }

            Divider().padding(.leading, 44)

            NavigationLink {
                SetHomeView(viewModel: SetHomeViewModel(pet: viewModel.pet, petRepository: petRepository, locationService: locationService))
            } label: {
                actionRow(systemImage: "house.fill", title: "Set Home")
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionRow(systemImage: String, title: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .contentShape(Rectangle())
    }

    // MARK: - Stats

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let position = viewModel.pet.lastPosition {
                StatTile(systemImage: "gauge.with.dots.needle.67percent", title: "Speed", value: formattedSpeed(position.speedKilometersPerHour))
                if let battery = position.batteryLevelPercent {
                    StatTile(systemImage: batteryIcon(for: battery), title: "Battery", value: formattedPercent(battery))
                }
            }
            if let totalDistance = viewModel.totalTrailDistanceMeters {
                StatTile(systemImage: "shoeprints.fill", title: "Distance Today", value: formattedDistance(totalDistance))
            }
            if let lastSeenAt = viewModel.pet.lastSeenAt {
                StatTile(systemImage: "clock", title: "Last Update", value: lastSeenAt.formatted(.relative(presentation: .named)))
            }
        }
    }

    private struct StatTile: View {
        let systemImage: String
        let title: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Location

    @ViewBuilder
    private var locationRow: some View {
        if let address = viewModel.pet.lastPosition?.address, !address.isEmpty {
            Label(address, systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let coordinate = viewModel.pet.lastPosition?.coordinate {
            // Traccar only reports an address when a geocoder is configured
            // server-side — fall back to coordinates so this row is never empty.
            Label(formattedCoordinate(coordinate), systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Formatting

    private func formattedSpeed(_ kilometersPerHour: Double) -> String {
        kilometersPerHour.formatted(.number.precision(.fractionLength(0))) + " km/h"
    }

    private func formattedPercent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 {
            meters.formatted(.number.precision(.fractionLength(0))) + " m"
        } else {
            (meters / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
        }
    }

    private func formattedCoordinate(_ coordinate: Coordinate) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func batteryIcon(for percent: Double) -> String {
        switch percent {
        case ..<13: "battery.0"
        case ..<38: "battery.25"
        case ..<63: "battery.50"
        case ..<88: "battery.75"
        default: "battery.100"
        }
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
