import SwiftUI
import LibrePawKit

/// A pet's excursions as a calendar: a month grid, a week of 24-hour
/// bars, and a single day's timeline, switchable at the top, with a
/// summary of what's shown and arrows to move back and forth. Tapping a
/// day in the month or week opens that day, tapping an excursion in the
/// day opens its detail.
struct ExcursionsView: View {
    let petRepository: PetRepository
    @State private var viewModel: ExcursionsViewModel

    init(viewModel: ExcursionsViewModel, petRepository: PetRepository) {
        _viewModel = State(initialValue: viewModel)
        self.petRepository = petRepository
    }

    var body: some View {
        content
            .background(Color.appBackground)
            .navigationTitle("Excursions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Today") {
                        withAnimation { viewModel.goToToday() }
                    }
                    .disabled(viewModel.isShowingToday)
                }
            }
            .navigationDestination(for: Excursion.self) { excursion in
                ExcursionDetailView(viewModel: ExcursionDetailViewModel(
                    excursion: excursion,
                    petID: viewModel.pet.id,
                    petRepository: petRepository
                ))
            }
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.excursions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Couldn't Load Excursions", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
            }
        } else if viewModel.excursions.isEmpty {
            ContentUnavailableView {
                Label("No Excursions Yet", systemImage: "pawprint")
            } description: {
                Text("Once \(viewModel.pet.name) leaves home and comes back, excursions will show up here. Make sure a home location is set first.")
            }
        } else {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Picker("View", selection: $viewModel.mode.animation()) {
                        ForEach(ExcursionCalendarMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    periodHeader
                    summary

                    switch viewModel.mode {
                    case .month:
                        MonthGrid(viewModel: viewModel)
                    case .week:
                        WeekRows(viewModel: viewModel)
                    case .day:
                        DayTimeline(viewModel: viewModel, scrollProxy: proxy)
                    }
                }
                .padding()
            }
            .refreshable { await viewModel.refresh() }
            }
        }
    }

    private var periodHeader: some View {
        HStack {
            Button {
                withAnimation { viewModel.step(-1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Previous"))
            Spacer()
            Text(periodTitle)
                .font(.headline)
                .foregroundStyle(.appText)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                withAnimation { viewModel.step(1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Next"))
        }
    }

    private var periodTitle: String {
        let interval = viewModel.shownInterval
        let locale = LocalizationBundle.currentLocale
        switch viewModel.mode {
        case .month:
            return interval.start.formatted(Date.FormatStyle(locale: locale).month(.wide).year())
        case .week:
            // "23.–29. Nov. 2026", the system's own compact range format.
            return (interval.start..<interval.end.addingTimeInterval(-1))
                .formatted(Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, locale: locale))
        case .day:
            return interval.start.formatted(Date.FormatStyle(locale: locale).weekday(.wide).day().month(.wide).year())
        }
    }

    private var summary: some View {
        let totals = viewModel.mode == .day ? viewModel.totals(on: viewModel.anchor) : viewModel.shownTotals()
        return HStack(spacing: 0) {
            summaryItem(value: "\(totals.walkCount)", title: "Walks")
            Divider().frame(height: 32)
            summaryItem(value: Formatting.distance(totals.distanceMeters), title: "Distance")
            Divider().frame(height: 32)
            summaryItem(value: Formatting.duration(totals.durationSeconds), title: "Time Away")
        }
        .padding(.vertical, 10)
        .background(.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryItem(value: String, title: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(.appText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.appSecondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Month

/// The shown month as a grid of days, each with its distance and a dot per
/// excursion, tinted darker the farther the pet walked that day.
private struct MonthGrid: View {
    let viewModel: ExcursionsViewModel

    private var weekdaySymbols: [String] {
        var calendar = viewModel.calendar
        calendar.locale = LocalizationBundle.currentLocale
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    /// Every slot the same size, whether it holds a day with excursions,
    /// one without, or nothing (before the 1st, after the last).
    static let cellHeight: CGFloat = 58

    var body: some View {
        let maximum = viewModel.maximumDailyDistanceInShownMonth
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.bold())
                    .foregroundStyle(.appSecondaryText)
            }
            ForEach(Array(viewModel.monthGrid.joined().enumerated()), id: \.offset) { _, day in
                if let day {
                    Button {
                        withAnimation { viewModel.show(day: day) }
                    } label: {
                        MonthDayCell(
                            day: day,
                            totals: viewModel.totals(on: day),
                            maximum: maximum,
                            isToday: viewModel.calendar.isDateInToday(day),
                            isFuture: day > .now
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(height: Self.cellHeight)
                }
            }
        }
    }
}

private struct MonthDayCell: View {
    let day: Date
    let totals: ExcursionsViewModel.DayTotals
    let maximum: Double
    let isToday: Bool
    let isFuture: Bool

    private var level: Double {
        maximum > 0 ? totals.distanceMeters / maximum : 0
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(day.formatted(.dateTime.day()))
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .foregroundStyle(isFuture ? Color.appSecondaryText.opacity(0.5) : (level > 0.6 ? .white : .appText))
            if totals.walkCount > 0 {
                Text(Formatting.decimal(totals.distanceMeters / 1_000))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(level > 0.6 ? .white : .appSecondaryText)
                HStack(spacing: 2) {
                    ForEach(0..<min(totals.walkCount, 4), id: \.self) { _ in
                        Circle()
                            .fill(level > 0.6 ? Color.white : Color.appPrimaryDark)
                            .frame(width: 4, height: 4)
                    }
                }
            } else {
                Spacer().frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: MonthGrid.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(totals.walkCount > 0 ? Color.appPrimaryDark.opacity(0.15 + 0.8 * level) : Color.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isToday ? Color.appPrimaryDark : .clear, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Formatting.date(day)))
        .accessibilityValue(Text("\(totals.walkCount) · \(Formatting.distance(totals.distanceMeters))"))
    }
}

// MARK: - Week

/// One row per day of the shown week: the date, a 24-hour bar with each
/// excursion as a block where it happened, and that day's totals.
private struct WeekRows: View {
    let viewModel: ExcursionsViewModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.shownDays, id: \.self) { day in
                Button {
                    withAnimation { viewModel.show(day: day) }
                } label: {
                    row(day)
                }
                .buttonStyle(.plain)
            }
            HourScale()
                .padding(.leading, 52)
                .padding(.trailing, 74)
        }
    }

    private func row(_ day: Date) -> some View {
        let totals = viewModel.totals(on: day)
        let locale = LocalizationBundle.currentLocale
        let isToday = viewModel.calendar.isDateInToday(day)
        return HStack(spacing: 8) {
            VStack(spacing: 0) {
                Text(day.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.appSecondaryText)
                Text(day.formatted(.dateTime.day()))
                    .font(.headline)
                    .foregroundStyle(isToday ? Color.appPrimaryDark : .appText)
            }
            .frame(width: 44)

            DayBar(excursions: viewModel.excursions(on: day)) { excursion in
                viewModel.dayFractions(of: excursion, on: day)
            }
            .frame(height: 28)

            VStack(alignment: .trailing, spacing: 0) {
                if totals.walkCount > 0 {
                    Text(Formatting.distance(totals.distanceMeters))
                        .font(.caption.bold())
                        .foregroundStyle(.appText)
                    Text(Formatting.duration(totals.durationSeconds))
                        .font(.caption2)
                        .foregroundStyle(.appSecondaryText)
                } else {
                    Text("–")
                        .foregroundStyle(.appSecondaryText)
                }
            }
            .frame(width: 66, alignment: .trailing)
        }
        .padding(8)
        .background(.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A day as a horizontal bar, each excursion a block spanning when it
/// happened.
private struct DayBar: View {
    let excursions: [Excursion]
    let fractions: (Excursion) -> ClosedRange<Double>?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appSecondaryText.opacity(0.1))
                // Quarter-day ticks, so a block's time of day can be read.
                ForEach([0.25, 0.5, 0.75], id: \.self) { tick in
                    Rectangle()
                        .fill(Color.appSecondaryText.opacity(0.2))
                        .frame(width: 1)
                        .offset(x: geometry.size.width * tick)
                }
                ForEach(excursions) { excursion in
                    if let range = fractions(excursion) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ExcursionStyle.color(for: excursion))
                            .frame(width: max(3, geometry.size.width * (range.upperBound - range.lowerBound)))
                            .offset(x: geometry.size.width * range.lowerBound)
                    }
                }
            }
        }
    }
}

/// "0  6  12  18  24" under the week's day bars.
private struct HourScale: View {
    var body: some View {
        GeometryReader { geometry in
            ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                Text("\(hour)")
                    .font(.system(size: 9))
                    .foregroundStyle(.appSecondaryText)
                    .fixedSize()
                    .position(x: geometry.size.width * Double(hour) / 24, y: 6)
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Day

/// The shown day as a 24-hour timeline, each excursion a block from its
/// start to its end, like a day in a calendar app. Scrolled to the first
/// excursion of the day.
private struct DayTimeline: View {
    let viewModel: ExcursionsViewModel
    let scrollProxy: ScrollViewProxy

    private let hourHeight: CGFloat = 54
    private let labelWidth: CGFloat = 44

    static func hourID(_ hour: Int) -> String { "timeline-hour-\(hour)" }

    var body: some View {
        let day = viewModel.anchor
        let excursions = viewModel.excursions(on: day)
        VStack(alignment: .leading, spacing: 12) {
            if excursions.isEmpty {
                Text("\(viewModel.pet.name) wasn't on any excursion this day.")
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
            ZStack(alignment: .topLeading) {
                hourGrid
                ForEach(excursions) { excursion in
                    if let range = viewModel.dayFractions(of: excursion, on: day) {
                        NavigationLink(value: excursion) {
                            ExcursionBlock(excursion: excursion, routeText: excursion.routeText { viewModel.homeName(forHomeID: $0) })
                        }
                        .buttonStyle(.plain)
                        .frame(height: max(30, hourHeight * 24 * (range.upperBound - range.lowerBound)), alignment: .top)
                        .padding(.leading, labelWidth + 6)
                        .offset(y: hourHeight * 24 * range.lowerBound)
                    }
                }
                if viewModel.calendar.isDateInToday(day) {
                    nowLine
                }
            }
            .frame(height: hourHeight * 24, alignment: .top)
        }
        // A day mostly has its excursions in a few hours, jump to the
        // first one rather than starting at midnight. Waits a moment so
        // the timeline is laid out when it's just been switched to.
        .task(id: viewModel.anchor) {
            guard let hour = viewModel.firstExcursionHour(on: viewModel.anchor) else { return }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation { scrollProxy.scrollTo(Self.hourID(max(0, hour - 1)), anchor: .top) }
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(String(format: "%02d:00", hour))
                        .id(Self.hourID(hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.appSecondaryText)
                        .frame(width: labelWidth, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle()
                        .fill(Color.appSecondaryText.opacity(0.2))
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
    }

    private var nowLine: some View {
        let startOfDay = viewModel.calendar.startOfDay(for: .now)
        let fraction = Date.now.timeIntervalSince(startOfDay) / 86_400
        return HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Rectangle().fill(.red).frame(height: 1.5)
        }
        .padding(.leading, labelWidth + 2)
        .offset(y: hourHeight * 24 * fraction - 4)
    }
}

/// One excursion on the day timeline: its times, distance and duration,
/// marked when it's still going on, lost the tracker's signal, or was
/// probably a car or train ride.
private struct ExcursionBlock: View {
    let excursion: Excursion
    let routeText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(ExcursionStyle.color(for: excursion))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(timeText)
                        .font(.caption.bold())
                        .foregroundStyle(.appText)
                    if let badge = ExcursionStyle.badge(for: excursion) {
                        Label(badge.title, systemImage: badge.systemImage)
                            .font(.caption2.bold())
                            .foregroundStyle(badge.color)
                            .labelStyle(.titleAndIcon)
                    }
                }
                HStack(spacing: 8) {
                    if let distance = excursion.distanceMeters {
                        Text(Formatting.distance(distance))
                    }
                    if let duration = excursion.duration {
                        Text(Formatting.duration(duration))
                    }
                    if let routeText {
                        Text(routeText)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.appSecondaryText)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.appSecondaryText)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ExcursionStyle.color(for: excursion).opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var timeText: String {
        guard let end = excursion.endTime else {
            return "\(Formatting.time(excursion.startTime))"
        }
        return localized("%@ to %@", Formatting.time(excursion.startTime), Formatting.time(end))
    }
}

/// How an excursion is colored and labeled on the calendar, the same
/// meanings the old list's labels had.
private enum ExcursionStyle {
    static func color(for excursion: Excursion) -> Color {
        if excursion.isOngoing { return .orange }
        if excursion.isLikelyVehicleTrip { return .appSecondaryText }
        return .appPrimaryDark
    }

    static func badge(for excursion: Excursion) -> (title: LocalizedStringKey, systemImage: String, color: Color)? {
        if excursion.isOngoing { return ("Away now", "hare.fill", .orange) }
        if excursion.endedWithLostSignal { return ("Signal lost", "antenna.radiowaves.left.and.right.slash", .appSecondaryText) }
        if excursion.isLikelyVehicleTrip { return ("Car ride?", "car.fill", .appSecondaryText) }
        return nil
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ExcursionsView(
            viewModel: ExcursionsViewModel(pet: .previewOnline, petRepository: PreviewPetRepository()),
            petRepository: PreviewPetRepository()
        )
    }
}
#endif
