import SwiftUI
import Charts
import LibrePawKit

/// The charts on the Statistics screen. Values are plotted in units a
/// chart axis can show plainly (kilometers, minutes), labels go through
/// `Formatting` so they match the rest of the app and its language.

// MARK: - Per day

/// Bars per day with a dashed average line. Touching or dragging over the
/// chart shows that day's own value in the header instead of the average.
struct DailyChartSection: View {
    let title: LocalizedStringKey
    let days: [ExcursionStatistics.Day]
    let value: (ExcursionStatistics.Day) -> Double
    let average: Double
    /// The y axis's unit, "km" or "min".
    let unit: String
    let format: (Double) -> String

    @State private var selectedDate: Date?

    private var selectedDay: ExcursionStatistics.Day? {
        guard let selectedDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        StatsSection(title: title, systemImage: "chart.bar.xaxis") {
            if let selectedDay {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(format(value(selectedDay))).font(.subheadline.bold())
                    Text(Formatting.date(selectedDay.date)).font(.caption2).foregroundStyle(.appSecondaryText)
                }
            } else {
                Text("Avg. \(format(average))")
                    .font(.subheadline.bold())
                    .foregroundStyle(.appSecondaryText)
            }
        } content: {
            Chart {
                ForEach(days) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Value", value(day))
                    )
                    .foregroundStyle(selectedDay == nil || selectedDay == day ? Color.appPrimaryDark : Color.appPrimary.opacity(0.4))
                }
                if average > 0 {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxisLabel(unit)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 180)
        }
    }
}

// MARK: - Per week

/// The average distance per day, week by week, rather than each week's
/// total: the range's first and current week usually aren't complete, and
/// their totals would read like a slump that never happened.
struct WeeklyTrendSection: View {
    let weeks: [ExcursionStatistics.Week]

    var body: some View {
        StatsSection(title: "Weekly Trend", systemImage: "chart.line.uptrend.xyaxis") {
            Chart(weeks) { week in
                AreaMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("km", week.averageDistancePerDay / 1_000))
                    .foregroundStyle(LinearGradient(colors: [Color.appPrimary.opacity(0.5), Color.appPrimary.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("km", week.averageDistancePerDay / 1_000))
                    .foregroundStyle(Color.appPrimaryDark)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("km", week.averageDistancePerDay / 1_000))
                    .foregroundStyle(Color.appPrimaryDark)
                    .annotation(position: .top) {
                        Text(Formatting.distance(week.averageDistancePerDay))
                            .font(.caption2)
                            .foregroundStyle(.appSecondaryText)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxisLabel("km")
            .frame(height: 180)
            Text("Average distance per day, week by week.")
                .font(.caption)
                .foregroundStyle(.appSecondaryText)
        }
    }
}

// MARK: - Weekdays

struct WeekdaySection: View {
    let weekdays: [ExcursionStatistics.WeekdayAverage]

    private func name(_ weekday: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = LocalizationBundle.currentLocale
        return calendar.shortWeekdaySymbols[weekday - 1]
    }

    var body: some View {
        StatsSection(title: "Weekdays", systemImage: "calendar.day.timeline.left") {
            Chart(weekdays) { weekday in
                BarMark(x: .value("Weekday", name(weekday.weekday)), y: .value("km", weekday.distanceMeters / 1_000))
                    .foregroundStyle(Color.appPrimaryDark)
                    .annotation(position: .top) {
                        Text(Formatting.distance(weekday.distanceMeters))
                            .font(.caption2)
                            .foregroundStyle(.appSecondaryText)
                    }
            }
            .chartYAxisLabel("km")
            .frame(height: 170)
            Text("Average distance on each day of the week.")
                .font(.caption)
                .foregroundStyle(.appSecondaryText)
        }
    }
}

// MARK: - Time of day

struct StartHourSection: View {
    let startHours: [Int]

    var body: some View {
        StatsSection(title: "Time of Day", systemImage: "clock.fill") {
            Chart(Array(startHours.enumerated()), id: \.offset) { hour, count in
                BarMark(x: .value("Hour", hour), y: .value("Walks", count))
                    .foregroundStyle(Color.appPrimaryDark)
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) { Text("\(hour):00") }
                    }
                }
            }
            .frame(height: 150)
            Text("When walks start, by hour of the day.")
                .font(.caption)
                .foregroundStyle(.appSecondaryText)
        }
    }
}

// MARK: - Distributions

struct DistributionSection: View {
    let statistics: ExcursionStatistics

    var body: some View {
        StatsSection(title: "How Long and How Far", systemImage: "chart.bar.doc.horizontal") {
            Text("Walks by duration")
                .font(.subheadline)
                .foregroundStyle(.appSecondaryText)
            bucketChart(statistics.durationBuckets) { Formatting.durationBucket($0) }
            Text("Walks by distance")
                .font(.subheadline)
                .foregroundStyle(.appSecondaryText)
            bucketChart(statistics.distanceBuckets) { Formatting.distanceBucket($0) }
        }
    }

    private func bucketChart(_ buckets: [ExcursionStatistics.Bucket], label: @escaping (ExcursionStatistics.Bucket) -> String) -> some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("Range", label(bucket)), y: .value("Walks", bucket.count))
                .foregroundStyle(Color.appPrimaryDark)
                .annotation(position: .top) {
                    if bucket.count > 0 {
                        Text("\(bucket.count)").font(.caption2).foregroundStyle(.appSecondaryText)
                    }
                }
        }
        .chartYAxis(.hidden)
        .frame(height: 130)
    }
}

// MARK: - Battery

struct BatterySection: View {
    let history: [StatsViewModel.BatteryPoint]
    let curve: BatteryCurve
    let isEstimated: Bool

    var body: some View {
        StatsSection(title: "Battery", systemImage: "battery.75percent") {
            Chart(history) { point in
                AreaMark(x: .value("Time", point.time), y: .value("%", point.percent))
                    .foregroundStyle(LinearGradient(colors: [Color.appPrimary.opacity(0.45), Color.appPrimary.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.time), y: .value("%", point.percent))
                    .foregroundStyle(Color.appPrimaryDark)
                RuleMark(y: .value("Low", 20))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 170)

            VStack(alignment: .leading, spacing: 4) {
                if let timeLeft = history.last.flatMap({ isEstimated ? curve.activeTimeLeft(atPercent: $0.percent) : nil }) {
                    Label("Enough for about \(Formatting.batteryTimeLeft(timeLeft)) out and about", systemImage: "figure.walk")
                }
                if let runtime = curve.averageActiveRuntime {
                    Label("Full charge: about \(Formatting.batteryTimeLeft(runtime)) out and about", systemImage: "bolt.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.appSecondaryText)
        }
    }
}
