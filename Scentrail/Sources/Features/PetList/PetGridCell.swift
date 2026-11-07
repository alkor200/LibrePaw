import SwiftUI
import ScentrailKit

/// One pet's bubble in the Pets grid: photo (or paw placeholder), name,
/// status, and a battery badge when the tracker has reported one.
struct PetGridCell: View {
    let pet: Pet
    let petRepository: PetRepository

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                PetAnnotationView(pet: pet, petRepository: petRepository, size: 84)

                if let battery = pet.lastPosition?.batteryLevelPercent {
                    Image(systemName: batteryIcon(for: battery))
                        .font(.caption2)
                        .foregroundStyle(battery < 20 ? .red : .secondary)
                        .padding(5)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 4, y: 4)
                }
            }

            VStack(spacing: 2) {
                Text(pet.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        switch pet.status {
        case .online:
            "Online"
        case .offline, .unknown:
            if let lastSeenAt = pet.lastSeenAt {
                lastSeenAt.formatted(.relative(presentation: .named))
            } else {
                pet.status.label
            }
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 20) {
        PetGridCell(pet: .previewOnline, petRepository: PreviewPetRepository())
        PetGridCell(pet: .previewOffline, petRepository: PreviewPetRepository())
    }
    .padding()
}
