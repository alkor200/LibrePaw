import Foundation

/// A minimal dynamic JSON value, used to decode Traccar's free-form
/// `attributes` dictionaries (which can contain strings, numbers, bools, or
/// nested objects depending on the device protocol) without pulling in a
/// third-party "AnyCodable" dependency.
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case null

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

extension JSONValue: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            // Nested objects/arrays are not needed by Scentrail today; treat as null
            // rather than failing the whole decode of the containing device/position.
            self = .null
        }
    }
}
