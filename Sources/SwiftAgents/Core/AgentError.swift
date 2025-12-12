// AgentError.swift
// SwiftAgents Framework
//
// Comprehensive error types for agent operations.

import Foundation

/// Errors that can occur during agent execution.
public enum AgentError: Error, Sendable, Equatable {
    // MARK: - Input Errors

    /// The input provided to the agent was empty or invalid.
    case invalidInput(reason: String)

    // MARK: - Execution Errors

    /// The agent was cancelled before completion.
    case cancelled

    /// The agent exceeded the maximum number of iterations.
    case maxIterationsExceeded(iterations: Int)

    /// The agent execution timed out.
    case timeout(duration: Duration)

    // MARK: - Tool Errors

    /// A tool with the given name was not found.
    case toolNotFound(name: String)

    /// A tool failed to execute.
    case toolExecutionFailed(toolName: String, underlyingError: String)

    /// Invalid arguments were provided to a tool.
    case invalidToolArguments(toolName: String, reason: String)

    // MARK: - Model Errors

    /// The inference provider is not available.
    case inferenceProviderUnavailable(reason: String)

    /// The model context window was exceeded.
    case contextWindowExceeded(tokenCount: Int, limit: Int)

    /// The model response violated content guidelines.
    case guardrailViolation

    /// The language is not supported by the model.
    case unsupportedLanguage(language: String)

    /// The model failed to generate a response.
    case generationFailed(reason: String)

    // MARK: - Internal Errors

    /// An internal error occurred.
    case internalError(reason: String)
}

// MARK: - LocalizedError Conformance

extension AgentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .cancelled:
            return "Agent execution was cancelled"
        case .maxIterationsExceeded(let iterations):
            return "Agent exceeded maximum iterations (\(iterations))"
        case .timeout(let duration):
            return "Agent execution timed out after \(duration)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .toolExecutionFailed(let toolName, let error):
            return "Tool '\(toolName)' failed: \(error)"
        case .invalidToolArguments(let toolName, let reason):
            return "Invalid arguments for tool '\(toolName)': \(reason)"
        case .inferenceProviderUnavailable(let reason):
            return "Inference provider unavailable: \(reason)"
        case .contextWindowExceeded(let count, let limit):
            return "Context window exceeded: \(count) tokens (limit: \(limit))"
        case .guardrailViolation:
            return "Response violated content guidelines"
        case .unsupportedLanguage(let language):
            return "Language not supported: \(language)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .internalError(let reason):
            return "Internal error: \(reason)"
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension AgentError: CustomDebugStringConvertible {
    public var debugDescription: String {
        "AgentError.\(self)"
    }
}
