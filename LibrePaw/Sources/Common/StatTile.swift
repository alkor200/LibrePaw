import SwiftUI

/// A small rounded card with an icon, a value and a caption, used for Pet
/// Detail's live values and the Statistics screen's figures.
struct StatTile: View {
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
