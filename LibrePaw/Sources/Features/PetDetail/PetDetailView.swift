import SwiftUI
import UIKit
import LibrePawKit

/// Destinations reachable from `PetDetailView`, pushed via `NavigationLink(value:)`.
///
/// Deliberately value-based rather than the eager `NavigationLink { Destination() }`
/// closure form: `PetDetailView.body` re-evaluates frequently (live WebSocket
/// position updates), and an eager destination closure gets re-invoked on every
/// such re-render, which tears down and rebuilds anything already pushed on top
/// of it, the push visually "snaps back" to this screen. Routing through a
/// `Hashable` value keeps the pushed destination stable across those re-renders.
private enum PetDetailRoute: Hashable {
    case findPet
    case map
    case trail
    case excursions
    case homes
    case sharePet
}

struct PetDetailView: View {
    let petRepository: PetRepository
    let locationService: LocationService
    @State private var viewModel: PetDetailViewModel
    @State private var isShowingEditPet = false
    /// Shown in place of whatever `PetAnnotationView` would otherwise fetch,
    /// right after a successful edit, see its doc comment for why the fetch
    /// alone can't be relied on to notice the change.
    @State private var justSavedPhoto: UIImage?

    init(viewModel: PetDetailViewModel, petRepository: PetRepository, locationService: LocationService) {
        self.petRepository = petRepository
        self.locationService = locationService
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if viewModel.pet.lastPosition != nil {
                    findButton
                }
                actionsCard
                statGrid
                locationRow
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle(viewModel.pet.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PetDetailRoute.self) { route in
            switch route {
            case .findPet:
                FindPetView(viewModel: FindPetViewModel(pet: viewModel.pet, petRepository: petRepository, locationService: locationService))
            case .map:
                PetMapView(petRepository: petRepository, locationService: locationService, initialFocus: viewModel.pet)
            case .trail:
                TrailView(viewModel: TrailViewModel(pet: viewModel.pet, petRepository: petRepository), petRepository: petRepository)
            case .excursions:
                ExcursionsView(
                    viewModel: ExcursionsViewModel(pet: viewModel.pet, petRepository: petRepository),
                    petRepository: petRepository
                )
            case .homes:
                HomesView(
                    viewModel: HomesViewModel(pet: viewModel.pet, petRepository: petRepository),
                    petRepository: petRepository,
                    locationService: locationService
                )
            case .sharePet:
                SharePetView(viewModel: SharePetViewModel(pet: viewModel.pet, petRepository: petRepository))
            }
        }
        .task {
            await viewModel.loadTodaysTrail()
        }
        .task {
            await viewModel.loadLifetimeStats()
        }
        .task {
            await viewModel.loadTodaysExcursions()
        }
        .task {
            await viewModel.loadPermissions()
        }
        .sheet(isPresented: $isShowingEditPet) {
            EditPetView(currentName: viewModel.pet.name) { newName in
                try await viewModel.rename(to: newName)
            } onSavePhoto: { jpegData in
                try await viewModel.setPhoto(jpegData: jpegData)
                justSavedPhoto = UIImage(data: jpegData)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            PetAnnotationView(pet: viewModel.pet, petRepository: petRepository, size: 96, overrideImage: justSavedPhoto)
            Text(viewModel.pet.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(statusCaption)
                .font(.subheadline)
                .foregroundStyle(viewModel.pet.status.tintColor)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusCaption: String {
        switch viewModel.pet.status {
        case .online:
            localized("Online")
        case .offline, .unknown:
            if let lastSeenAt = viewModel.pet.lastSeenAt {
                "\(viewModel.pet.status.label) · \(lastSeenAt.formatted(.relative(presentation: .named)))"
            } else {
                viewModel.pet.status.label
            }
        }
    }

    // MARK: - Find button

    private var findButton: some View {
        NavigationLink(value: PetDetailRoute.findPet) {
            Label("Find \(viewModel.pet.name)", systemImage: "location.north.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(spacing: 0) {
            // Editing a device (its name or photo) needs Traccar's own
            // `deviceReadonly`/`readonly` to both be clear, hidden rather
            // than left tappable toward a save that would just fail (see
            // ADR-0023).
            if viewModel.permissions?.canManageDevice == true {
                Button {
                    isShowingEditPet = true
                } label: {
                    actionRow(systemImage: "pencil", title: "Edit \(viewModel.pet.name)")
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 44).overlay(Color.appBorder)
            }

            NavigationLink(value: PetDetailRoute.map) {
                actionRow(systemImage: "map.fill", title: "View on Map")
            }

            // Trail and Excursions are both built from Traccar's reports
            // endpoint, hidden together rather than leading somewhere that
            // would just error, when the account has reports disabled (see
            // ADR-0023).
            if viewModel.permissions?.canViewExcursions == true {
                Divider().padding(.leading, 44).overlay(Color.appBorder)

                NavigationLink(value: PetDetailRoute.trail) {
                    actionRow(systemImage: "point.topleft.down.curvedto.point.bottomright.up", title: "Trail")
                }

                Divider().padding(.leading, 44).overlay(Color.appBorder)

                NavigationLink(value: PetDetailRoute.excursions) {
                    actionRow(systemImage: "figure.walk", title: "Excursions")
                }
            }

            Divider().padding(.leading, 44).overlay(Color.appBorder)

            // Anyone can manage homes now (see ADR-0017/ADR-0018's
            // follow-up), a non-admin's home is only ever visible to
            // themselves, which `HomesView` explains, but there's no
            // reason to hide the screen entirely over that limitation:
            // viewing works even with read-only access, `HomesView` itself
            // hides the add/edit/delete affordances (see ADR-0023).
            NavigationLink(value: PetDetailRoute.homes) {
                actionRow(systemImage: "house.fill", title: "\(viewModel.pet.name)'s Homes")
            }

            // Sharing stays admin-only: granting another Traccar account
            // access to a device requires an administrator server-side,
            // confirmed against a live server, there's no non-admin path
            // to make this work at all, so the entry point is hidden
            // rather than leading somewhere useless.
            if viewModel.permissions?.isAdministrator == true {
                Divider().padding(.leading, 44).overlay(Color.appBorder)

                NavigationLink(value: PetDetailRoute.sharePet) {
                    actionRow(systemImage: "person.badge.plus", title: "Share \(viewModel.pet.name)")
                }
            }
        }
        .background(.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionRow(systemImage: String, title: LocalizedStringKey) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text(title)
                .foregroundStyle(.appText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.appSecondaryText)
        }
        .padding()
        .contentShape(Rectangle())
    }

    // MARK: - Stats

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let position = viewModel.pet.lastPosition {
                StatTile(systemImage: "gauge.with.dots.needle.67percent", title: "Speed", value: formattedSpeed(position.speedKilometersPerHour))
            }
            // Grouped with Speed rather than at the end, so the two
            // "right now" tiles share a row, then today's and lifetime's
            // stats each get their own row as a pair.
            if let lastSeenAt = viewModel.pet.lastSeenAt {
                StatTile(systemImage: "clock", title: "Last Update", value: lastSeenAt.formatted(.relative(presentation: .named)))
            }
            if let position = viewModel.pet.lastPosition, let battery = position.batteryLevelPercent {
                StatTile(systemImage: batteryIcon(for: battery), title: "Battery", value: formattedPercent(battery))
            }
            if let totalDistance = viewModel.totalTrailDistanceMeters {
                StatTile(systemImage: "shoeprints.fill", title: "Distance Today", value: formattedDistance(totalDistance))
            }
            if let timeAwayToday = viewModel.totalTimeAwayTodaySeconds {
                StatTile(systemImage: "figure.walk", title: "Time Away Today", value: formattedDuration(timeAwayToday))
            }
            if let lifetimeStats = viewModel.lifetimeStats, lifetimeStats.totalDistanceMeters > 0 {
                StatTile(systemImage: "map.fill", title: "Total Distance", value: formattedDistance(lifetimeStats.totalDistanceMeters))
            }
            if let lifetimeStats = viewModel.lifetimeStats, lifetimeStats.totalDurationSeconds > 0 {
                StatTile(systemImage: "figure.walk.motion", title: "Total Time Away", value: formattedDuration(lifetimeStats.totalDurationSeconds))
            }
        }
    }

    private struct StatTile: View {
        let systemImage: String
        let title: LocalizedStringKey
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
                    .foregroundStyle(.appSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .background(.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let coordinate = viewModel.pet.lastPosition?.coordinate {
            // Traccar only reports an address when a geocoder is configured
            // server-side, fall back to coordinates so this row is never empty.
            Label(formattedCoordinate(coordinate), systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.appSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        let d = localized("duration.days.abbreviation")
        let h = localized("duration.hours.abbreviation")
        let m = localized("duration.minutes.abbreviation")
        if days > 0 {
            return "\(days)\(d) \(hours)\(h)"
        } else if hours > 0 {
            return "\(hours)\(h) \(minutes)\(m)"
        } else {
            return "\(minutes)\(m)"
        }
    }

    private func formattedCoordinate(_ coordinate: Coordinate) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
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
