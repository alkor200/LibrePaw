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

    static func string(from date: Date) -> String {
        withoutFractionalSeconds.string(from: date)
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
