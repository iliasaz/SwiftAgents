// GuardrailError.swift
// SwiftAgents Framework
//
// Comprehensive error types for guardrail execution.

import Foundation

// MARK: - GuardrailError

/// Errors related to guardrail execution.
public enum GuardrailError: Error, Sendable, LocalizedError, Equatable {
    /// Input guardrail tripwire was triggered
    case inputTripwireTriggered(
        guardrailName: String,
        message: String?,
        outputInfo: SendableValue?
    )
    
    /// Output guardrail tripwire was triggered
    case outputTripwireTriggered(
        guardrailName: String,
        agentName: String,
        message: String?,
        outputInfo: SendableValue?
    )
    
    /// Tool input guardrail tripwire was triggered
    case toolInputTripwireTriggered(
        guardrailName: String,
        toolName: String,
        message: String?,
        outputInfo: SendableValue?
    )
    
    /// Tool output guardrail tripwire was triggered
    case toolOutputTripwireTriggered(
        guardrailName: String,
        toolName: String,
        message: String?,
        outputInfo: SendableValue?
    )
    
    /// Guardrail execution failed
    case executionFailed(guardrailName: String, underlyingError: String)
    
    public var errorDescription: String? {
        switch self {
        case .inputTripwireTriggered(let name, let message, _):
            return "Input guardrail '\(name)' tripwire triggered: \(message ?? "No message")"
        case .outputTripwireTriggered(let name, let agentName, let message, _):
            return "Output guardrail '\(name)' tripwire triggered for agent '\(agentName)': \(message ?? "No message")"
        case .toolInputTripwireTriggered(let name, let toolName, let message, _):
            return "Tool input guardrail '\(name)' tripwire triggered for tool '\(toolName)': \(message ?? "No message")"
        case .toolOutputTripwireTriggered(let name, let toolName, let message, _):
            return "Tool output guardrail '\(name)' tripwire triggered for tool '\(toolName)': \(message ?? "No message")"
        case .executionFailed(let name, let error):
            return "Guardrail '\(name)' execution failed: \(error)"
        }
    }
}

// MARK: CustomDebugStringConvertible

extension GuardrailError: CustomDebugStringConvertible {
    public var debugDescription: String {
        "GuardrailError.\(self)"
    }
}
