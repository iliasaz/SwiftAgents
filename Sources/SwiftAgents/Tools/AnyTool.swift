//
//  AnyTool.swift
//  SwiftAgents
//
//  Created as part of audit remediation - Phase 4
//

import Foundation

// MARK: - AnyTool

/// Type-erased wrapper for any Tool
///
/// Enables storing heterogeneous tools in collections without
/// losing type information at runtime:
/// ```swift
/// let tools: [AnyTool] = [
///     AnyTool(calculatorTool),
///     AnyTool(weatherTool),
///     AnyTool(searchTool)
/// ]
///
/// for tool in tools {
///     print("Tool: \(tool.name) - \(tool.description)")
/// }
/// ```
public struct AnyTool: Tool, Sendable {
    // MARK: Public

    public var name: String { box._name }
    public var description: String { box._description }
    public var parameters: [ToolParameter] { box._parameters }

    public init(_ tool: some Tool) {
        box = ToolBox(tool)
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        try await box._execute(arguments: arguments)
    }

    // MARK: Private

    private let box: any AnyToolBox
}

// MARK: - AnyToolBox

private protocol AnyToolBox: Sendable {
    var _name: String { get }
    var _description: String { get }
    var _parameters: [ToolParameter] { get }

    func _execute(arguments: [String: SendableValue]) async throws -> SendableValue
}

// MARK: - ToolBox

private struct ToolBox<T: Tool>: AnyToolBox, Sendable {
    // MARK: Internal

    var _name: String { tool.name }
    var _description: String { tool.description }
    var _parameters: [ToolParameter] { tool.parameters }

    init(_ tool: T) { self.tool = tool }

    func _execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        try await tool.execute(arguments: arguments)
    }

    // MARK: Private

    private let tool: T
}
