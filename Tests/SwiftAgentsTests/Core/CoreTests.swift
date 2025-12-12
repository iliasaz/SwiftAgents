// CoreTests.swift
// SwiftAgentsTests
//
// Tests for core types: SendableValue, AgentConfiguration, and AgentError
// NOTE: Full tests pending Phase 1 completion

import Testing
import Foundation
@testable import SwiftAgents

// MARK: - SendableValue Tests

@Suite("SendableValue Tests")
struct SendableValueTests {

    @Test("Literal initialization")
    func literalInitialization() {
        let nullValue: SendableValue = nil
        let boolValue: SendableValue = true
        let intValue: SendableValue = 42
        let doubleValue: SendableValue = 3.14
        let stringValue: SendableValue = "hello"

        #expect(nullValue == .null)
        #expect(boolValue == .bool(true))
        #expect(intValue == .int(42))
        #expect(doubleValue == .double(3.14))
        #expect(stringValue == .string("hello"))
    }

    @Test("Type-safe accessors")
    func typeSafeAccessors() {
        let intVal: SendableValue = .int(42)
        let doubleVal: SendableValue = .double(3.14)
        let stringVal: SendableValue = .string("hello")
        let boolVal: SendableValue = .bool(true)

        #expect(intVal.intValue == 42)
        #expect(doubleVal.doubleValue == 3.14)
        #expect(stringVal.stringValue == "hello")
        #expect(boolVal.boolValue == true)
    }

    @Test("Codable conformance")
    func codableConformance() throws {
        let original: SendableValue = [
            "string": "hello",
            "number": 42,
            "bool": true
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SendableValue.self, from: data)

        #expect(decoded == original)
    }
}

// MARK: - AgentConfiguration Tests

@Suite("AgentConfiguration Tests")
struct AgentConfigurationTests {

    @Test("Default configuration")
    func defaultConfiguration() {
        let config = AgentConfiguration.default

        #expect(config.maxIterations == 10)
        #expect(config.timeout == .seconds(60))
        #expect(config.temperature == 1.0)
    }

    @Test("Custom initialization")
    func customInitialization() {
        let config = AgentConfiguration(
            maxIterations: 5,
            timeout: .seconds(30),
            temperature: 0.5
        )

        #expect(config.maxIterations == 5)
        #expect(config.timeout == .seconds(30))
        #expect(config.temperature == 0.5)
    }
}

// MARK: - AgentError Tests

@Suite("AgentError Tests")
struct AgentErrorTests {

    @Test("Error descriptions exist")
    func errorDescriptions() {
        let errors: [AgentError] = [
            .invalidInput(reason: "empty"),
            .cancelled,
            .maxIterationsExceeded(iterations: 10),
            .toolNotFound(name: "missing_tool"),
        ]

        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test("Equatable conformance")
    func equatableConformance() {
        let error1 = AgentError.toolNotFound(name: "test")
        let error2 = AgentError.toolNotFound(name: "test")
        let error3 = AgentError.toolNotFound(name: "other")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}

// MARK: - Placeholder Tests for Phase 1 Completion

@Suite("Core Types - Pending Phase 1", .disabled("Requires Phase 1 completion"))
struct CoreTypesPendingTests {

    @Test("ToolCall and ToolResult")
    func toolCallAndResult() {
        // Pending Phase 1: ToolCall, ToolResult types
    }

    @Test("AgentResult builder")
    func agentResultBuilder() {
        // Pending Phase 1: AgentResult.Builder
    }

    @Test("TokenUsage")
    func tokenUsage() {
        // Pending Phase 1: TokenUsage type
    }
}
