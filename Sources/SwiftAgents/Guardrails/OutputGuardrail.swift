// OutputGuardrail.swift
// SwiftAgents Framework
//
// Protocol and implementations for validating agent output before returning to users.

import Foundation

// MARK: - OutputGuardrail

/// Protocol for validating agent output before returning to users.
///
/// `OutputGuardrail` enables validation and filtering of agent outputs to ensure they meet
/// safety, quality, or policy requirements. Output guardrails receive the agent's output text,
/// the agent instance, and optional context for making validation decisions.
///
/// Common use cases:
/// - Content filtering (profanity, sensitive data)
/// - Quality checks (minimum length, coherence)
/// - Policy compliance (tone, formatting)
/// - PII detection and redaction
///
/// Example:
/// ```swift
/// let guardrail = ClosureOutputGuardrail(name: "content_filter") { output, agent, context in
///     if output.contains("badword") {
///         return .tripwire(
///             message: "Profanity detected",
///             outputInfo: .dictionary(["word": .string("badword")])
///         )
///     }
///     return .passed()
/// }
///
/// let result = try await guardrail.validate(
///     "Agent response text",
///     agent: myAgent,
///     context: context
/// )
///
/// if result.tripwireTriggered {
///     print("Output blocked: \(result.message ?? "")")
/// }
/// ```
public protocol OutputGuardrail: Sendable {
    /// The name of this guardrail for identification and logging.
    var name: String { get }

    /// Validates an agent's output.
    ///
    /// - Parameters:
    ///   - output: The output text from the agent to validate.
    ///   - agent: The agent that produced this output.
    ///   - context: Optional orchestration context with shared state.
    /// - Returns: A result indicating whether the output passed validation.
    /// - Throws: An error if validation fails unexpectedly.
    func validate(_ output: String, agent: any Agent, context: AgentContext?) async throws -> GuardrailResult
}

// MARK: - ClosureOutputGuardrail

/// A closure-based implementation of `OutputGuardrail`.
///
/// `ClosureOutputGuardrail` wraps a validation closure, making it easy to create
/// custom output guardrails without defining new types.
///
/// The closure receives:
/// - `output`: The agent's output text
/// - `agent`: The agent instance that produced the output
/// - `context`: Optional shared orchestration context
///
/// The closure is marked `@Sendable` to ensure thread-safety across async boundaries.
///
/// Example:
/// ```swift
/// // PII detection guardrail
/// let piiGuardrail = ClosureOutputGuardrail(name: "pii_detector") { output, agent, context in
///     let patterns = ["\\d{3}-\\d{2}-\\d{4}", "\\d{16}"] // SSN, credit card
///     for pattern in patterns {
///         if let _ = output.range(of: pattern, options: .regularExpression) {
///             return .tripwire(
///                 message: "PII detected in output",
///                 outputInfo: .dictionary(["pattern": .string(pattern)])
///             )
///         }
///     }
///     return .passed(message: "No PII detected")
/// }
///
/// // Length validation
/// let lengthGuardrail = ClosureOutputGuardrail(name: "min_length") { output, _, _ in
///     if output.count < 10 {
///         return .tripwire(message: "Output too short")
///     }
///     return .passed()
/// }
///
/// // Context-aware validation
/// let contextGuardrail = ClosureOutputGuardrail(name: "strict_mode") { output, _, context in
///     if let mode = await context?.get("validation_mode")?.stringValue, mode == "strict" {
///         // Apply stricter validation
///         if output.contains("forbidden") {
///             return .tripwire(message: "Forbidden content in strict mode")
///         }
///     }
///     return .passed()
/// }
/// ```
public struct ClosureOutputGuardrail: OutputGuardrail, Sendable {
    // MARK: - Properties

    /// The name of this guardrail.
    public let name: String

    /// The validation handler closure.
    private let handler: @Sendable (String, any Agent, AgentContext?) async throws -> GuardrailResult

    // MARK: - Initialization

    /// Creates a closure-based output guardrail.
    ///
    /// - Parameters:
    ///   - name: The name of this guardrail for identification.
    ///   - handler: The validation closure that receives output, agent, and context.
    ///
    /// Example:
    /// ```swift
    /// let guardrail = ClosureOutputGuardrail(name: "profanity_filter") { output, agent, context in
    ///     if output.contains("badword") {
    ///         return .tripwire(message: "Profanity detected")
    ///     }
    ///     return .passed()
    /// }
    /// ```
    public init(
        name: String,
        handler: @escaping @Sendable (String, any Agent, AgentContext?) async throws -> GuardrailResult
    ) {
        self.name = name
        self.handler = handler
    }

    // MARK: - OutputGuardrail

    /// Validates the agent output by calling the handler closure.
    ///
    /// - Parameters:
    ///   - output: The output text from the agent to validate.
    ///   - agent: The agent that produced this output.
    ///   - context: Optional orchestration context with shared state.
    /// - Returns: The result from the handler closure.
    /// - Throws: Any error thrown by the handler closure.
    public func validate(_ output: String, agent: any Agent, context: AgentContext?) async throws -> GuardrailResult {
        try await handler(output, agent, context)
    }
}
