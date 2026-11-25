import SwiftUI

/// A battery drawn like the one in the iPhone's status bar: an outline
/// with a terminal nub, filled up to the level, and the percentage itself
/// inside it. Red below 20 %, the same threshold `PetGridCell`'s badge
/// uses.
struct BatteryGauge: View {
    /// 0 to 100.
    let percent: Double
    var height: CGFloat = 14

    private var level: Double { min(100, max(0, percent)) / 100 }
    private var isLow: Bool { percent < 20 }
    private var width: CGFloat { height * 2.1 }

    var body: some View {
        HStack(spacing: height * 0.1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .strokeBorder(Color.appSecondaryText.opacity(0.6), lineWidth: 1)
                RoundedRectangle(cornerRadius: height * 0.2, style: .continuous)
                    .fill(isLow ? Color.red.opacity(0.45) : Color.appSecondaryText.opacity(0.45))
                    .padding(2)
                    .frame(width: max(height * 0.3, width * level))
                Text("\(Int(percent.rounded()))")
                    .font(.system(size: height * 0.72, weight: .bold).monospacedDigit())
                    .foregroundStyle(isLow ? Color.red : Color.appText)
                    .frame(width: width)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.appSecondaryText.opacity(0.6))
                .frame(width: height * 0.12, height: height * 0.4)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        BatteryGauge(percent: 100)
        BatteryGauge(percent: 48)
        BatteryGauge(percent: 12)
    }
    .padding()
}
#endif
