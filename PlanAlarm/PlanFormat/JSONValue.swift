import Foundation

/// A loosely-typed JSON tree, so the validator can report friendly, located errors
/// instead of `Codable`'s generic ones.
enum JSONValue: Sendable, Equatable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    /// A short rendering for error messages, e.g. `"75"`, `true`, `a list`.
    var brief: String {
        switch self {
        case .null: "null"
        case .bool(let value): value ? "true" : "false"
        case .number(let value):
            value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .string(let value):
            "\"" + (value.count > 40 ? String(value.prefix(40)) + "…" : value) + "\""
        case .array: "a list"
        case .object: "an object"
        }
    }
}
