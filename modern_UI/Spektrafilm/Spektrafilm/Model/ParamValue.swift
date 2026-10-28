import Foundation

/// A JSON scalar for `params_delta`.
enum ParamValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case double(Double), bool(Bool), string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else { self = .string(try c.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .string(let s): try c.encode(s)
        }
    }
    var description: String {
        switch self {
        case .double(let d): String(format: "%.4g", d)
        case .bool(let b): b ? "true" : "false"
        case .string(let s): s
        }
    }
    var doubleValue: Double? { if case .double(let d) = self { d } else { nil } }
    var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    var stringValue: String? { if case .string(let s) = self { s } else { nil } }
}
