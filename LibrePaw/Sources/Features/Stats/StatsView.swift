import SwiftUI
import Charts
import LibrePawKit

/// Everything there is to see about a pet's walks: totals and averages,
/// day-by-day and week-by-week charts, an activity calendar, when and how
/// long the pet usually walks, records, and the battery. Reached from Pet
/// Detail, which keeps only the tracker's live values itself.
struct StatsView: View {
    @State private var viewModel: StatsViewModel

    init(viewModel: StatsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $viewModel.range) {
                    ForEach(StatsRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if let statistics = viewModel.statistics, !statistics.days.isEmpty, statistics.walkCount > 0 || statistics.ongoing != nil {
                    content(statistics)
                } else if !viewModel.isLoading, viewModel.errorMessage == nil {
                    ContentUnavailableView(
                        "No Walks Yet",
                        systemImage: "chart.bar",
                        description: Text("Statistics appear here once \(viewModel.pet.name) has been on an excursion in this period.")
                    )
                }
                if !viewModel.batteryHistory.isEmpty {
                    BatterySection(
                        history: viewModel.batteryHistory,
                        curve: viewModel.batteryCurve,
                        isEstimated: viewModel.batteryIsEstimated
                    )
                }
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoading, viewModel.statistics == nil {
                ProgressView()
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't Load Statistics", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await viewModel.load() } }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await viewModel.recalculate() }
                    } label: {
                        Label("Recalculate Lifetime Stats", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRecalculating)
                } label: {
                    Image(systemName: viewModel.isRecalculating ? "hourglass" : "ellipsis.circle")
                }
            }
        }
        .alert(
            "Couldn't Recalculate",
            isPresented: Binding(
                get: { viewModel.recalculateErrorMessage != nil },
                set: { if !$0 { viewModel.recalculateErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.recalculateErrorMessage ?? "")
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func content(_ statistics: ExcursionStatistics) -> some View {
        OverviewGrid(statistics: statistics)
        DailyChartSection(
            title: "Distance per Day",
            days: statistics.days,
            value: { $0.distanceMeters / 1_000 },
            average: statistics.averageDistancePerDay / 1_000,
            unit: "km",
            format: { Formatting.distance($0 * 1_000) }
        )
        DailyChartSection(
            title: "Time Away per Day",
            days: statistics.days,
            value: { $0.durationSeconds / 60 },
            average: statistics.averageDurationPerDay / 60,
            unit: "min",
            format: { Formatting.duration($0 * 60) }
        )
        if statistics.weeks.count > 1 {
            WeeklyTrendSection(weeks: statistics.weeks)
        }
        StatsSection(title: "Activity Calendar", systemImage: "calendar") {
            ActivityCalendarView(days: statistics.days)
        }
        WeekdaySection(weekdays: statistics.weekdays)
        StartHourSection(startHours: statistics.startHours)
        if statistics.walkCount > 0 {
            DistributionSection(statistics: statistics)
            WalkScatterSection(walks: statistics.walks)
            RecordsSection(statistics: statistics)
        }
        if statistics.vehicleTripCount > 0 || statistics.lostSignalCount > 0 {
            FootnoteSection(statistics: statistics)
        }
    }
}

// MARK: - Overview

private struct OverviewGrid: View {
    let statistics: ExcursionStatistics

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(systemImage: "map.fill", title: "Total Distance", value: Formatting.distance(statistics.totalDistanceMeters))
            StatTile(systemImage: "pawprint.fill", title: "Total Time Away", value: Formatting.duration(statistics.totalDurationSeconds))
            StatTile(systemImage: "figure.walk", title: "Walks", value: "\(statistics.walkCount)")
            StatTile(systemImage: "calendar.badge.clock", title: "Walks per Day", value: Formatting.decimal(statistics.averageWalksPerDay))
            StatTile(systemImage: "chart.bar.fill", title: "Avg. Distance per Day", value: Formatting.distance(statistics.averageDistancePerDay))
            StatTile(systemImage: "calendar", title: "Avg. Time Away per Day", value: Formatting.duration(statistics.averageDurationPerDay))
            if let distance = statistics.averageDistancePerWalk, let duration = statistics.averageDurationPerWalk {
                StatTile(systemImage: "ruler", title: "Avg. Distance per Walk", value: Formatting.distance(distance))
                StatTile(systemImage: "stopwatch", title: "Avg. Walk Duration", value: Formatting.duration(duration))
            }
            if let speed = statistics.averageSpeedKilometersPerHour {
                StatTile(systemImage: "gauge.with.dots.needle.67percent", title: "Avg. Pace", value: Formatting.speed(speed, fractionDigits: 1))
                StatTile(systemImage: "flame.fill", title: "Current Streak", value: Formatting.days(statistics.currentStreak))
            }
        }
    }
}

// MARK: - Records

private struct RecordsSection: View {
    let statistics: ExcursionStatistics

    var body: some View {
        StatsSection(title: "Records", systemImage: "trophy.fill") {
            VStack(spacing: 0) {
                if let walk = statistics.farthestWalk, let distance = walk.distanceMeters {
                    row("Farthest Walk", systemImage: "arrow.left.and.right", value: Formatting.distance(distance), date: walk.startTime)
                }
                if let walk = statistics.longestWalk, let duration = walk.duration {
                    row("Longest Walk", systemImage: "hourglass", value: Formatting.duration(duration), date: walk.startTime)
                }
                if let walk = statistics.fastestWalk, let speed = walk.averageSpeedKilometersPerHour {
                    row("Fastest Walk", systemImage: "hare.fill", value: Formatting.speed(speed, fractionDigits: 1), date: walk.startTime)
                }
                if let day = statistics.mostActiveDay {
                    row("Most Active Day", systemImage: "star.fill", value: Formatting.distance(day.distanceMeters), date: day.date, showsTime: false)
                }
                row("Longest Streak", systemImage: "flame.fill", value: Formatting.days(statistics.longestStreak), date: nil)
                if let walk = statistics.earliestStartingWalk() {
                    row("Earliest Start", systemImage: "sunrise.fill", value: Formatting.time(walk.startTime), date: walk.startTime, showsTime: false)
                }
                if let walk = statistics.latestStartingWalk() {
                    row("Latest Start", systemImage: "moon.stars.fill", value: Formatting.time(walk.startTime), date: walk.startTime, showsTime: false)
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, value: String, date: Date?, showsTime: Bool = true) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.appText)
                if let date {
                    Text(showsTime ? Formatting.dateTime(date) : Formatting.date(date))
                        .font(.caption)
                        .foregroundStyle(.appSecondaryText)
                }
            }
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundStyle(.appText)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Footnote

private struct FootnoteSection: View {
    let statistics: ExcursionStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if statistics.vehicleTripCount > 0 {
                Label("Likely car or train rides, not counted: \(statistics.vehicleTripCount)", systemImage: "car.fill")
            }
            if statistics.lostSignalCount > 0 {
                Label("Walks where the tracker lost its signal, counted as far as recorded: \(statistics.lostSignalCount)", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
        .font(.footnote)
        .foregroundStyle(.appSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section container

/// A titled card every chart and list on this screen sits in.
struct StatsSection<Content: View, Accessory: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    init(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.appText)
                Spacer()
                accessory()
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        StatsView(viewModel: StatsViewModel(pet: .previewOnline, petRepository: PreviewPetRepository()))
    }
}
#endif
