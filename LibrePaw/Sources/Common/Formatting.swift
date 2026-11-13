import Foundation

/// The one place distances, durations, speeds and times are turned into
/// text, so every screen shows the same value the same way, in the
/// current app language's own number format (see
/// ``LocalizationBundle/currentLocale``).
///
/// These used to be private helpers repeated per screen, and the copies
/// had drifted apart: Excursions printed "1.2 km" via `String(format:)`
/// while Pet Detail printed "1,2 km" for the same distance in German, and
/// durations over a day read "26h 5m" in one place and "1d 2h" in another.
enum Formatting {
    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return number(meters, fractionDigits: 0) + " m"
        }
        return number(meters / 1000, fractionDigits: 1) + " km"
    }

    /// "42 min" under an hour, "3h 5m" under a day, "2d 4h" beyond that
    /// (unit abbreviations localized).
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        let d = localized("duration.days.abbreviation")
        let h = localized("duration.hours.abbreviation")
        let m = localized("duration.minutes.abbreviation")
        if days > 0 {
            return "\(days)\(d) \(hours)\(h)"
        } else if hours > 0 {
            return "\(hours)\(h) \(minutes)\(m)"
        } else {
            return "\(minutes) \(localized("duration.minutes.unit"))"
        }
    }

    static func speed(_ kilometersPerHour: Double, fractionDigits: Int = 0) -> String {
        number(kilometersPerHour, fractionDigits: fractionDigits) + " km/h"
    }

    /// `percent` is 0 to 100, e.g. a battery level.
    static func percent(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(0)).locale(LocalizationBundle.currentLocale))
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: LocalizationBundle.currentLocale))
    }

    static func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: LocalizationBundle.currentLocale))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: LocalizationBundle.currentLocale))
    }

    /// "5 minutes ago", "yesterday", ...
    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(LocalizationBundle.currentLocale))
    }

    private static func number(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(LocalizationBundle.currentLocale))
    }
}
