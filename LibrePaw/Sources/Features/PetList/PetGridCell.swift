import SwiftUI
import LibrePawKit

/// One pet's bubble in the Pets grid: photo (or paw placeholder), name,
/// status, and a battery badge when the tracker has reported one.
struct PetGridCell: View {
    let pet: Pet
    let petRepository: PetRepository
    /// See `PetRepository.batteryCurve`, cached there, so cheap to ask for
    /// on every appearance.
    @State private var batteryCurve: BatteryCurve = .generic

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                PetAnnotationView(pet: pet, petRepository: petRepository, size: 84)
                    .task(id: pet.id) {
                        guard pet.lastPosition?.batteryLevelPercent == nil, pet.lastPosition?.batteryVoltage != nil else { return }
                        batteryCurve = await petRepository.batteryCurve(forPetID: pet.id)
                    }

                if let battery = pet.lastPosition?.battery(using: batteryCurve)?.percent {
                    Image(systemName: batteryIcon(for: battery))
                        .font(.caption2)
                        .foregroundStyle(battery < 20 ? .red : .appSecondaryText)
                        .padding(5)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 4, y: 4)
                }
            }

            VStack(spacing: 2) {
                Text(pet.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.appText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.appSecondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        switch pet.status {
        case .online:
            localized("Online")
        case .offline, .unknown:
            if let lastSeenAt = pet.lastSeenAt {
                Formatting.relative(lastSeenAt)
            } else {
                pet.status.label
            }
        }
    }
}

#if DEBUG
#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 20) {
        PetGridCell(pet: .previewOnline, petRepository: PreviewPetRepository())
        PetGridCell(pet: .previewOffline, petRepository: PreviewPetRepository())
    }
    .padding()
}
#endif
