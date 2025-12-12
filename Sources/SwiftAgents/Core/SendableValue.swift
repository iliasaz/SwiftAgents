// SendableValue.swift
// SwiftAgents Framework
//
// A type-safe, Sendable container for dynamic values used in tool arguments and results.

import Foundation

/// A type-safe, Sendable container for dynamic values used in tool arguments and results.
/// Replaces `[String: Any]` which cannot conform to `Sendable`.
public enum SendableValue: Sendable, Equatable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SendableValue])
    case dictionary([String: SendableValue])

    // MARK: - Convenience Initializers

    public init(_ value: Bool) { self = .bool(value) }
    public init(_ value: Int) { self = .int(value) }
    public init(_ value: Double) { self = .double(value) }
    public init(_ value: String) { self = .string(value) }
    public init(_ value: [SendableValue]) { self = .array(value) }
    public init(_ value: [String: SendableValue]) { self = .dictionary(value) }

    // MARK: - Type-Safe Accessors

    /// Returns the Bool value if this is a `.bool`, otherwise nil.
    public var boolValue: Bool? {
        guard case .bool(let v) = self else { return nil }
        return v
    }

    /// Returns the Int value if this is an `.int`, otherwise nil.
    public var intValue: Int? {
        guard case .int(let v) = self else { return nil }
        return v
    }

    /// Returns the Double value if this is a `.double` or `.int`, otherwise nil.
    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    /// Returns the String value if this is a `.string`, otherwise nil.
    public var stringValue: String? {
        guard case .string(let v) = self else { return nil }
        return v
    }

    /// Returns the array if this is an `.array`, otherwise nil.
    public var arrayValue: [SendableValue]? {
        guard case .array(let v) = self else { return nil }
        return v
    }

    /// Returns the dictionary if this is a `.dictionary`, otherwise nil.
    public var dictionaryValue: [String: SendableValue]? {
        guard case .dictionary(let v) = self else { return nil }
        return v
    }

    /// Returns true if this is `.null`.
    public var isNull: Bool {
        guard case .null = self else { return false }
        return true
    }

    // MARK: - Subscript Access

    /// Access dictionary values by key.
    public subscript(key: String) -> SendableValue? {
        guard case .dictionary(let dict) = self else { return nil }
        return dict[key]
    }

    /// Access array values by index.
    public subscript(index: Int) -> SendableValue? {
        guard case .array(let arr) = self, index >= 0, index < arr.count else { return nil }
        return arr[index]
    }
}

// MARK: - ExpressibleBy Literals

extension SendableValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension SendableValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension SendableValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension SendableValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension SendableValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension SendableValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: SendableValue...) { self = .array(elements) }
}

extension SendableValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, SendableValue)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - CustomStringConvertible

extension SendableValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null: return "null"
        case .bool(let v): return String(v)
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .string(let v): return "\"\(v)\""
        case .array(let v): return "[\(v.map(\.description).joined(separator: ", "))]"
        case .dictionary(let v):
            let pairs = v.map { "\"\($0)\": \($1.description)" }.joined(separator: ", ")
            return "{\(pairs)}"
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension SendableValue: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .null: return "SendableValue.null"
        case .bool(let v): return "SendableValue.bool(\(v))"
        case .int(let v): return "SendableValue.int(\(v))"
        case .double(let v): return "SendableValue.double(\(v))"
        case .string(let v): return "SendableValue.string(\"\(v)\")"
        case .array(let v): return "SendableValue.array(\(v.map(\.debugDescription)))"
        case .dictionary(let v): return "SendableValue.dictionary(\(v))"
        }
    }
}
