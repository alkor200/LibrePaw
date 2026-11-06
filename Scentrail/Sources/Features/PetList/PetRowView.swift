import SwiftUI
import ScentrailKit

struct PetRowView: View {
    let pet: Pet

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(pet.status.tintColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: speciesSymbolName)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        switch pet.status {
        case .online:
            "Online"
        case .offline, .unknown:
            if let lastSeenAt = pet.lastSeenAt {
                "Last seen \(lastSeenAt.formatted(.relative(presentation: .named)))"
            } else {
                pet.status.label
            }
        }
    }

    private var speciesSymbolName: String {
        switch pet.species?.lowercased() {
        case "dog": "dog.fill"
        case "cat": "cat.fill"
        case "bird": "bird.fill"
        default: "pawprint.fill"
        }
    }
}

#Preview {
    List {
        PetRowView(pet: .previewOnline)
        PetRowView(pet: .previewOffline)
    }
}
