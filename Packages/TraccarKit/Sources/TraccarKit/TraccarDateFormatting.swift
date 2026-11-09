import Foundation

/// Traccar emits timestamps as ISO 8601 strings, sometimes with fractional
/// seconds and sometimes without, depending on the field and server version.
enum TraccarDateFormatting {
    // `ISO8601DateFormatter` is documented as thread-safe for concurrent use once
    // configured, so a shared instance accessed from multiple tasks is safe even
    // though the type itself predates `Sendable`.
    nonisolated(unsafe) private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        withFractionalSeconds.date(from: string) ?? withoutFractionalSeconds.date(from: string)
    }

    /// Used to format `from`/`to` query parameters sent back to Traccar
    /// (`fetchPositionHistory`, `fetchEvents`). Must retain fractional
    /// seconds: a date decoded from one of Traccar's own timestamps (e.g. a
    /// `geofenceEnter` event's `eventTime`) can carry a sub-second
    /// component, and formatting it back out with that dropped makes the
    /// resulting `to` bound strictly earlier than the real value whenever
    /// there is one, silently excluding the exact position that triggered
    /// the event from the response (confirmed live: this made
    /// `TraccarPetRepository.firstHomecomingPause`'s "last position in the
    /// bounded trail" always be the report *before* a real, on-time
    /// `geofenceEnter`, not the matching one, on effectively every
    /// excursion, not just the slow-device case ADR-0025 was written for).
    static func string(from date: Date) -> String {
        withFractionalSeconds.string(from: date)
    }

    /// A `JSONDecoder.DateDecodingStrategy` that understands both formats above.
    static var decodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected ISO 8601 date, got \(string)"
                )
            }
            return date
        }
    }
}
