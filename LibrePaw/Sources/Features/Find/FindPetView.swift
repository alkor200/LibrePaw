import SwiftUI
import UIKit
import LibrePawKit

/// An AirTag-style "Find" screen: a compass arrow that rotates to always
/// point toward the pet's last known position, with the distance below it.
/// Falls back to pointing relative to true north on devices (and the
/// Simulator) with no magnetometer (see ADR-0010).
struct FindPetView: View {
    @State private var viewModel: FindPetViewModel

    init(viewModel: FindPetViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            // Not just on `compassView` below: a plain `VStack` only sizes
            // itself to its widest child (the 260pt circle here), so
            // without this, `.background` only paints that narrow column,
            // leaving the system's own black fill visible down both sides
            // in dark mode, confirmed live. Applied once, here, so every
            // branch of `content` is covered rather than relying on each
            // one to remember its own `.frame`.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .navigationTitle("Find \(viewModel.pet.name)")
            .navigationBarTitleDisplayMode(.inline)
            .task { viewModel.start() }
            .onDisappear { viewModel.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.locationService.isDenied {
            deniedView
        } else if viewModel.pet.lastPosition == nil {
            ContentUnavailableView(
                "No Known Position",
                systemImage: "location.slash",
                description: Text("\(viewModel.pet.name)'s tracker hasn't reported a position yet.")
            )
        } else if viewModel.locationService.coordinate == nil {
            ProgressView("Finding your location…")
        } else {
            compassView
        }
    }

    private var compassView: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.appBorder, lineWidth: 2)
                    .frame(width: 260, height: 260)

                Image(systemName: "location.north.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(viewModel.arrowRotationDegrees ?? 0))
                    .animation(.easeOut(duration: 0.3), value: viewModel.arrowRotationDegrees)
            }

            VStack(spacing: 4) {
                Text(distanceText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.default, value: viewModel.distanceMeters)
                if let recordedAt = viewModel.pet.lastPosition?.recordedAt {
                    // `Text(_:style:)` ticks on its own every second, unlike a
                    // formatted string, it doesn't need the view to re-render.
                    (Text("Last position ") + Text(recordedAt, style: .relative))
                        .font(.subheadline)
                        .foregroundStyle(.appSecondaryText)
                }
            }

            if !viewModel.locationService.isHeadingAvailable {
                Label("Compass unavailable, pointing from true north instead.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.appSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Location Access Needed", systemImage: "location.slash")
        } description: {
            Text("LibrePaw needs your location to point you toward \(viewModel.pet.name).")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private var distanceText: String {
        guard let meters = viewModel.distanceMeters else { return "-" }
        if meters < 1000 {
            return meters.formatted(.number.precision(.fractionLength(0))) + " m"
        } else {
            return (meters / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        FindPetView(viewModel: FindPetViewModel(pet: .previewOnline, petRepository: PreviewPetRepository(), locationService: LocationService()))
    }
}
#endif
