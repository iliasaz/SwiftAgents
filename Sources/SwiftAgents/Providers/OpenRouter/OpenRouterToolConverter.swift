// OpenRouterToolConverter.swift
// SwiftAgents Framework
//
// Converts SwiftAgents tools to OpenRouter-compatible format.

import Foundation

// MARK: - OpenRouter Tool Definitions

/// OpenRouter tool definition with function type.
///
/// This represents the top-level tool object in OpenRouter's API format:
/// ```json
/// {
///     "type": "function",
///     "function": { ... }
/// }
/// ```
public struct OpenRouterToolDefinition: Sendable, Codable, Equatable {
    /// The type of tool. Currently always "function".
    public let type: String

    /// The function definition.
    public let function: OpenRouterFunctionDefinition

    /// Creates an OpenRouter tool definition.
    /// - Parameter function: The function definition.
    public init(function: OpenRouterFunctionDefinition) {
        self.type = "function"
        self.function = function
    }
}

/// OpenRouter function definition within a tool.
///
/// Contains the function's name, description, and JSON Schema parameters:
/// ```json
/// {
///     "name": "get_weather",
///     "description": "Gets the current weather",
///     "parameters": { ... }
/// }
/// ```
public struct OpenRouterFunctionDefinition: Sendable, Codable, Equatable {
    /// The name of the function.
    public let name: String

    /// A description of what the function does.
    public let description: String

    /// The parameters as a JSON Schema object.
    public let parameters: OpenRouterJSONSchema

    /// Creates an OpenRouter function definition.
    /// - Parameters:
    ///   - name: The function name.
    ///   - description: The function description.
    ///   - parameters: The JSON Schema for parameters.
    public init(name: String, description: String, parameters: OpenRouterJSONSchema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// JSON Schema representation for OpenRouter tool parameters.
///
/// Represents a JSON Schema object with type "object":
/// ```json
/// {
///     "type": "object",
///     "properties": { ... },
///     "required": ["param1", "param2"]
/// }
/// ```
public struct OpenRouterJSONSchema: Sendable, Codable, Equatable {
    /// The schema type. Always "object" for tool parameters.
    public let type: String

    /// The properties of the object.
    public let properties: [String: OpenRouterPropertySchema]

    /// The required property names.
    public let required: [String]

    /// Creates an OpenRouter JSON Schema.
    /// - Parameters:
    ///   - properties: The property schemas keyed by name.
    ///   - required: The names of required properties.
    public init(properties: [String: OpenRouterPropertySchema], required: [String]) {
        self.type = "object"
        self.properties = properties
        self.required = required
    }
}

/// Property schema for OpenRouter tool parameters.
///
/// Supports primitive types, arrays, and nested objects:
/// ```json
/// { "type": "string", "description": "..." }
/// { "type": "array", "items": { ... }, "description": "..." }
/// { "type": "object", "properties": { ... }, "required": [...], "description": "..." }
/// ```
public indirect enum OpenRouterPropertySchema: Sendable, Codable, Equatable {
    /// A string property.
    case string(description: String)

    /// An integer property.
    case integer(description: String)

    /// A number (double) property.
    case number(description: String)

    /// A boolean property.
    case boolean(description: String)

    /// An array property with element schema.
    case array(items: OpenRouterPropertySchema, description: String)

    /// An object property with nested properties.
    case object(properties: [String: OpenRouterPropertySchema], required: [String], description: String)

    /// An enum property with allowed values.
    case enumeration(values: [String], description: String)

    /// Any type (no type constraint).
    case any(description: String)

    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case items
        case properties
        case required
        case `enum`
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        let description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""

        switch type {
        case "string":
            if let enumValues = try container.decodeIfPresent([String].self, forKey: .enum) {
                self = .enumeration(values: enumValues, description: description)
            } else {
                self = .string(description: description)
            }
        case "integer":
            self = .integer(description: description)
        case "number":
            self = .number(description: description)
        case "boolean":
            self = .boolean(description: description)
        case "array":
            let items = try container.decode(OpenRouterPropertySchema.self, forKey: .items)
            self = .array(items: items, description: description)
        case "object":
            let properties = try container.decodeIfPresent([String: OpenRouterPropertySchema].self, forKey: .properties) ?? [:]
            let required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
            self = .object(properties: properties, required: required, description: description)
        default:
            self = .any(description: description)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .string(let description):
            try container.encode("string", forKey: .type)
            try container.encode(description, forKey: .description)

        case .integer(let description):
            try container.encode("integer", forKey: .type)
            try container.encode(description, forKey: .description)

        case .number(let description):
            try container.encode("number", forKey: .type)
            try container.encode(description, forKey: .description)

        case .boolean(let description):
            try container.encode("boolean", forKey: .type)
            try container.encode(description, forKey: .description)

        case .array(let items, let description):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encode(description, forKey: .description)

        case .object(let properties, let required, let description):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
            try container.encode(description, forKey: .description)

        case .enumeration(let values, let description):
            try container.encode("string", forKey: .type)
            try container.encode(values, forKey: .enum)
            try container.encode(description, forKey: .description)

        case .any(let description):
            try container.encode(description, forKey: .description)
        }
    }

    // MARK: - Conversion from ToolParameter.ParameterType

    /// Creates a property schema from a ToolParameter.ParameterType.
    /// - Parameters:
    ///   - parameterType: The parameter type to convert.
    ///   - description: The description for the property.
    /// - Returns: The corresponding OpenRouter property schema.
    public static func from(_ parameterType: ToolParameter.ParameterType, description: String) -> OpenRouterPropertySchema {
        switch parameterType {
        case .string:
            return .string(description: description)

        case .int:
            return .integer(description: description)

        case .double:
            return .number(description: description)

        case .bool:
            return .boolean(description: description)

        case .array(let elementType):
            let itemSchema = from(elementType, description: "")
            return .array(items: itemSchema, description: description)

        case .object(let properties):
            var propertySchemas: [String: OpenRouterPropertySchema] = [:]
            var required: [String] = []

            for param in properties {
                propertySchemas[param.name] = from(param.type, description: param.description)
                if param.isRequired {
                    required.append(param.name)
                }
            }

            return .object(properties: propertySchemas, required: required, description: description)

        case .oneOf(let options):
            return .enumeration(values: options, description: description)

        case .any:
            return .any(description: description)
        }
    }
}

// MARK: - OpenRouterToolCallParser

/// Parser for converting OpenRouter tool calls to SwiftAgents format.
///
/// Handles JSON parsing of tool call arguments and converts them to
/// `SendableValue` dictionaries compatible with SwiftAgents tools.
///
/// Example:
/// ```swift
/// let toolCall = OpenRouterToolCall(
///     id: "call_123",
///     function: OpenRouterFunctionCall(
///         name: "get_weather",
///         arguments: "{\"location\": \"San Francisco\"}"
///     )
/// )
///
/// if let parsed = OpenRouterToolCallParser.toParsedToolCall(toolCall) {
///     print("Tool: \(parsed.name)")
///     print("Args: \(parsed.arguments)")
/// }
/// ```
public enum OpenRouterToolCallParser: Sendable {
    /// Parses a JSON arguments string into a SendableValue dictionary.
    /// - Parameter jsonString: The JSON string to parse.
    /// - Returns: The parsed arguments, or nil if parsing fails.
    public static func parseArguments(_ jsonString: String) -> [String: SendableValue]? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var result: [String: SendableValue] = [:]
            for (key, value) in jsonObject {
                result[key] = SendableValue.fromJSONValue(value)
            }
            return result
        } catch {
            return nil
        }
    }

    /// Converts an OpenRouter tool call to a ParsedToolCall.
    /// - Parameter toolCall: The OpenRouter tool call to convert.
    /// - Returns: The parsed tool call, or nil if argument parsing fails.
    public static func toParsedToolCall(_ toolCall: OpenRouterToolCall) -> InferenceResponse.ParsedToolCall? {
        guard let arguments = parseArguments(toolCall.function.arguments) else {
            return nil
        }
        return InferenceResponse.ParsedToolCall(
            id: toolCall.id,
            name: toolCall.function.name,
            arguments: arguments
        )
    }

    /// Converts multiple OpenRouter tool calls to ParsedToolCalls.
    /// - Parameter toolCalls: The OpenRouter tool calls to convert.
    /// - Returns: Successfully parsed tool calls (failed parses are filtered out).
    public static func toParsedToolCalls(_ toolCalls: [OpenRouterToolCall]) -> [InferenceResponse.ParsedToolCall] {
        toolCalls.compactMap { toParsedToolCall($0) }
    }
}

// MARK: - SendableValue JSON Conversion Extension

public extension SendableValue {
    /// Creates a SendableValue from a JSON-compatible value.
    /// - Parameter value: The JSON value (from JSONSerialization).
    /// - Returns: The corresponding SendableValue.
    static func fromJSONValue(_ value: Any) -> SendableValue {
        switch value {
        case is NSNull:
            return .null

        case let bool as Bool:
            return .bool(bool)

        case let int as Int:
            return .int(int)

        case let double as Double:
            // Check if it's actually an integer stored as double
            if double.truncatingRemainder(dividingBy: 1) == 0,
               double >= Double(Int.min), double <= Double(Int.max) {
                return .int(Int(double))
            }
            return .double(double)

        case let string as String:
            return .string(string)

        case let array as [Any]:
            return .array(array.map { fromJSONValue($0) })

        case let dict as [String: Any]:
            var result: [String: SendableValue] = [:]
            for (key, val) in dict {
                result[key] = fromJSONValue(val)
            }
            return .dictionary(result)

        default:
            // Attempt to convert to string as fallback
            return .string(String(describing: value))
        }
    }
}

// MARK: - Tool Array Extension

public extension Array where Element == any Tool {
    /// Converts an array of tools to OpenRouter tool definitions.
    /// - Returns: The array of OpenRouter tool definitions.
    func toOpenRouterTools() -> [OpenRouterToolDefinition] {
        map { tool in
            var properties: [String: OpenRouterPropertySchema] = [:]
            var required: [String] = []

            for param in tool.parameters {
                properties[param.name] = OpenRouterPropertySchema.from(param.type, description: param.description)
                if param.isRequired {
                    required.append(param.name)
                }
            }

            let schema = OpenRouterJSONSchema(properties: properties, required: required)
            let function = OpenRouterFunctionDefinition(
                name: tool.name,
                description: tool.description,
                parameters: schema
            )

            return OpenRouterToolDefinition(function: function)
        }
    }
}

// MARK: - ToolDefinition Array Extension

public extension Array where Element == ToolDefinition {
    /// Converts an array of tool definitions to OpenRouter tool definitions.
    /// - Returns: The array of OpenRouter tool definitions.
    func toOpenRouterTools() -> [OpenRouterToolDefinition] {
        map { toolDef in
            var properties: [String: OpenRouterPropertySchema] = [:]
            var required: [String] = []

            for param in toolDef.parameters {
                properties[param.name] = OpenRouterPropertySchema.from(param.type, description: param.description)
                if param.isRequired {
                    required.append(param.name)
                }
            }

            let schema = OpenRouterJSONSchema(properties: properties, required: required)
            let function = OpenRouterFunctionDefinition(
                name: toolDef.name,
                description: toolDef.description,
                parameters: schema
            )

            return OpenRouterToolDefinition(function: function)
        }
    }
}
