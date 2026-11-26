import SwiftUI
import LibrePawKit

/// A calendar heatmap of the range, one square per day, one column per
/// week, darker the more the pet walked that day, the way GitHub shows
/// contributions. With few weeks the squares grow (up to a cap) and the
/// calendar is centered, with many they keep a minimum size and the
/// calendar scrolls, starting at the most recent week.
struct ActivityCalendarView: View {
    let days: [ExcursionStatistics.Day]

    private let minimumCellSize: CGFloat = 16
    private let maximumCellSize: CGFloat = 28
    private let spacing: CGFloat = 4
    private let labelWidth: CGFloat = 14
    @State private var availableWidth: CGFloat = 300

    private var cellSize: CGFloat {
        let weeks = CGFloat(max(columns.count, 1))
        let fitting = (availableWidth - labelWidth - spacing - (weeks - 1) * spacing) / weeks
        return min(maximumCellSize, max(minimumCellSize, fitting.rounded(.down)))
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = LocalizationBundle.currentLocale
        return calendar
    }

    /// Weeks as columns, each with 7 slots in the calendar's own weekday
    /// order, `nil` for slots outside the range.
    private var columns: [[ExcursionStatistics.Day?]] {
        var columns: [[ExcursionStatistics.Day?]] = []
        var current: [ExcursionStatistics.Day?] = Array(repeating: nil, count: 7)
        for day in days {
            let slot = (calendar.component(.weekday, from: day.date) - calendar.firstWeekday + 7) % 7
            if slot == 0, current.contains(where: { $0 != nil }) {
                columns.append(current)
                current = Array(repeating: nil, count: 7)
            }
            current[slot] = day
        }
        if current.contains(where: { $0 != nil }) { columns.append(current) }
        return columns
    }

    private var maximum: Double {
        days.map(\.distanceMeters).max() ?? 0
    }

    /// Whether every week fits without scrolling at the current cell size.
    private var fitsWithoutScrolling: Bool {
        let weeks = CGFloat(columns.count)
        return labelWidth + spacing + weeks * cellSize + (weeks - 1) * spacing <= availableWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if fitsWithoutScrolling {
                HStack(alignment: .top, spacing: spacing) {
                    weekdayLabels
                    weekColumns
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    weekdayLabels
                    ScrollView(.horizontal, showsIndicators: false) {
                        weekColumns
                    }
                    .defaultScrollAnchor(.trailing)
                }
            }
            legend
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: spacing) {
            ForEach(0..<7, id: \.self) { slot in
                Text(weekdayLabel(slot))
                    .font(.system(size: 9))
                    .foregroundStyle(.appSecondaryText)
                    .frame(width: labelWidth, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var weekColumns: some View {
        HStack(spacing: spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { slot in
                        cell(column[slot])
                    }
                }
            }
        }
    }

    private func weekdayLabel(_ slot: Int) -> String {
        // Every other row, like most calendar heatmaps, so the labels fit.
        guard slot % 2 == 0 else { return "" }
        let weekday = (calendar.firstWeekday - 1 + slot) % 7
        return calendar.veryShortWeekdaySymbols[weekday]
    }

    @ViewBuilder
    private func cell(_ day: ExcursionStatistics.Day?) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(for: day))
            .frame(width: cellSize, height: cellSize)
            .accessibilityLabel(day.map { "\(Formatting.date($0.date)): \(Formatting.distance($0.distanceMeters))" } ?? "")
    }

    private func color(for day: ExcursionStatistics.Day?) -> Color {
        guard let day else { return .clear }
        guard day.distanceMeters > 0, maximum > 0 else { return Color.appSecondaryText.opacity(0.12) }
        let level = day.distanceMeters / maximum
        return Color.appPrimaryDark.opacity(0.25 + 0.75 * level)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(level == 0 ? Color.appSecondaryText.opacity(0.12) : Color.appPrimaryDark.opacity(0.25 + 0.75 * level))
                    .frame(width: 10, height: 10)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(.appSecondaryText)
    }
}
