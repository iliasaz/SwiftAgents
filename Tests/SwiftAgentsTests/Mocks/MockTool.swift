// MockTool.swift
// SwiftAgentsTests
//
// Mock tool implementations for testing.

import Foundation
@testable import SwiftAgents

/// A configurable mock tool for testing.
///
/// Example:
/// ```swift
/// let tool = MockTool(
///     name: "weather",
///     result: .string("72°F and sunny")
/// )
/// let result = try await tool.execute(arguments: ["location": "NYC"])
/// ```
public struct MockTool: Tool, Sendable {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]

    private let resultHandler: @Sendable ([String: SendableValue]) async throws -> SendableValue

    /// Creates a mock tool with a fixed result.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The tool description.
    ///   - parameters: The tool parameters.
    ///   - result: The fixed result to return.
    public init(
        name: String = "mock_tool",
        description: String = "A mock tool for testing",
        parameters: [ToolParameter] = [],
        result: SendableValue = .string("mock result")
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.resultHandler = { _ in result }
    }

    /// Creates a mock tool with a custom handler.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The tool description.
    ///   - parameters: The tool parameters.
    ///   - handler: The custom execution handler.
    public init(
        name: String,
        description: String = "A mock tool for testing",
        parameters: [ToolParameter] = [],
        handler: @escaping @Sendable ([String: SendableValue]) async throws -> SendableValue
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.resultHandler = handler
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        try await resultHandler(arguments)
    }
}

/// A tool that throws an error when executed.
public struct FailingTool: Tool, Sendable {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]
    public let error: Error

    /// Creates a tool that always fails.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - error: The error to throw.
    public init(
        name: String = "failing_tool",
        error: Error = AgentError.toolExecutionFailed(toolName: "failing_tool", underlyingError: "Intentional failure")
    ) {
        self.name = name
        self.description = "A tool that always fails"
        self.parameters = []
        self.error = error
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        throw error
    }
}

/// A spy tool that records all invocations.
public actor SpyTool: Tool {
    nonisolated public let name: String
    nonisolated public let description: String
    nonisolated public let parameters: [ToolParameter]

    private var calls: [(arguments: [String: SendableValue], timestamp: Date)] = []
    private let result: SendableValue
    private let delay: Duration

    /// Creates a spy tool.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - result: The result to return.
    ///   - delay: Delay before returning.
    public init(
        name: String = "spy_tool",
        result: SendableValue = .string("spy result"),
        delay: Duration = .zero
    ) {
        self.name = name
        self.description = "A spy tool that records calls"
        self.parameters = []
        self.result = result
        self.delay = delay
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        calls.append((arguments, Date()))

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        return result
    }

    /// The number of times the tool was called.
    public var callCount: Int {
        calls.count
    }

    /// The last call arguments, if any.
    public var lastCall: (arguments: [String: SendableValue], timestamp: Date)? {
        calls.last
    }

    /// All recorded calls.
    public var allCalls: [(arguments: [String: SendableValue], timestamp: Date)] {
        calls
    }

    /// Resets the recorded calls.
    public func reset() {
        calls = []
    }

    /// Returns true if the tool was called with the given argument.
    public func wasCalledWith(argument key: String, value: SendableValue) -> Bool {
        calls.contains { call in
            call.arguments[key] == value
        }
    }
}

/// A tool that returns the arguments it received (echo).
public struct EchoTool: Tool, Sendable {
    public let name = "echo"
    public let description = "Returns the arguments it received"
    public let parameters: [ToolParameter] = [
        ToolParameter(name: "message", description: "Message to echo", type: .string, isRequired: false)
    ]

    public init() {}

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        .dictionary(arguments)
    }
}
