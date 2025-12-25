# SwiftAgents Comprehensive Implementation Plan

> Complete context for implementing OpenAI SDK parity - Phases 1-6

---

## Table of Contents
1. [Phase 1: Guardrails System](#phase-1-guardrails-system)
2. [Phase 2: Streaming Events & RunHooks](#phase-2-streaming-events--runhooks)
3. [Phase 3: Session & TraceContext](#phase-3-session--tracecontext)
4. [Phase 4: Enhanced Handoffs & MultiProvider](#phase-4-enhanced-handoffs--multiprovider)
5. [Phase 5: Polish Features](#phase-5-polish-features)
6. [Phase 6: Future Enhancements](#phase-6-future-enhancements)

---

## Existing SwiftAgents Patterns to Follow

### File Organization
```
Sources/SwiftAgents/
├── Core/           # Protocols, base types, errors
├── Agents/         # Agent implementations
├── Tools/          # Tool system
├── Memory/         # Memory implementations
├── Orchestration/  # Multi-agent coordination
├── Observability/  # Tracing, metrics
├── Providers/      # Inference providers
├── Resilience/     # Retry, circuit breaker
└── Guardrails/     # NEW - Create this directory
```

### Naming Conventions
- Protocols: `SomethingProtocol` or just noun (e.g., `Tracer`, `Tool`)
- Actors: Use for shared mutable state
- Structs: Prefer for data types
- Errors: `SomethingError` enum with `LocalizedError` conformance

### Existing Key Files to Reference
- **Protocol Pattern**: `Sources/SwiftAgents/Tools/Tool.swift`
- **Actor Pattern**: `Sources/SwiftAgents/Tools/Tool.swift` (ToolRegistry)
- **Error Pattern**: `Sources/SwiftAgents/Core/AgentError.swift`
- **Builder Pattern**: `Sources/SwiftAgents/Agents/AgentBuilder.swift`
- **Event Pattern**: `Sources/SwiftAgents/Core/AgentEvent.swift`

---

## Phase 1: Guardrails System

### Overview
Implement input/output validation at agent and tool levels with tripwire triggers that can halt execution.

### OpenAI Reference Implementation

```python
# OpenAI's GuardrailFunctionOutput
@dataclass
class GuardrailFunctionOutput:
    output_info: Any = None           # Additional info about the check
    tripwire_triggered: bool = False  # If True, raises exception

# OpenAI's InputGuardrail
@dataclass
class InputGuardrail(Generic[TContext]):
    guardrail_function: Callable[
        [RunContextWrapper[TContext], Agent[Any], str | list[TResponseInputItem]],
        MaybeAwaitable[GuardrailFunctionOutput],
    ]
    name: str | None = None
    run_in_parallel: bool = True  # Run concurrently with agent or before

# OpenAI's OutputGuardrail
@dataclass
class OutputGuardrail(Generic[TContext]):
    guardrail_function: Callable[
        [RunContextWrapper[TContext], Agent[Any], Any],
        MaybeAwaitable[GuardrailFunctionOutput],
    ]
    name: str | None = None

# OpenAI's ToolInputGuardrail
@dataclass
class ToolInputGuardrail:
    guardrail_function: Callable[
        [ToolInputGuardrailData],
        MaybeAwaitable[ToolGuardrailFunctionOutput],
    ]
    name: str | None = None

# OpenAI's exceptions
class InputGuardrailTripwireTriggered(Exception):
    guardrail: InputGuardrail
    output: GuardrailFunctionOutput

class OutputGuardrailTripwireTriggered(Exception):
    guardrail: OutputGuardrail
    agent: Agent
    agent_output: Any
    output: GuardrailFunctionOutput
```

### SwiftAgents Implementation

#### File 1: `Sources/SwiftAgents/Guardrails/GuardrailResult.swift`

```swift
import Foundation

/// Result of a guardrail validation check
public struct GuardrailResult: Sendable {
    /// Whether the tripwire was triggered (halts execution if true)
    public let tripwireTriggered: Bool

    /// Additional information about the validation result
    public let outputInfo: SendableValue?

    /// Optional message explaining the result
    public let message: String?

    /// Metadata about the validation
    public let metadata: [String: SendableValue]

    public init(
        tripwireTriggered: Bool,
        outputInfo: SendableValue? = nil,
        message: String? = nil,
        metadata: [String: SendableValue] = [:]
    ) {
        self.tripwireTriggered = tripwireTriggered
        self.outputInfo = outputInfo
        self.message = message
        self.metadata = metadata
    }

    /// Convenience for passing validation
    public static func pass(message: String? = nil) -> GuardrailResult {
        GuardrailResult(tripwireTriggered: false, message: message)
    }

    /// Convenience for failing validation
    public static func fail(
        message: String,
        outputInfo: SendableValue? = nil
    ) -> GuardrailResult {
        GuardrailResult(
            tripwireTriggered: true,
            outputInfo: outputInfo,
            message: message
        )
    }
}
```

#### File 2: `Sources/SwiftAgents/Guardrails/InputGuardrail.swift`

```swift
import Foundation

/// Protocol for validating agent inputs before execution
public protocol InputGuardrail: Sendable {
    /// Unique name for this guardrail (used in tracing)
    var name: String { get }

    /// Whether to run in parallel with the agent start (true) or before (false)
    var runInParallel: Bool { get }

    /// Validate the input before agent execution
    /// - Parameters:
    ///   - input: The user input string
    ///   - agent: The agent that will process the input
    ///   - context: The execution context
    /// - Returns: GuardrailResult indicating pass/fail
    func validate(
        _ input: String,
        agent: any Agent,
        context: AgentContext
    ) async throws -> GuardrailResult
}

// Default implementation
public extension InputGuardrail {
    var runInParallel: Bool { true }
}

/// Concrete input guardrail using a closure
public struct ClosureInputGuardrail: InputGuardrail {
    public let name: String
    public let runInParallel: Bool
    private let validation: @Sendable (String, any Agent, AgentContext) async throws -> GuardrailResult

    public init(
        name: String,
        runInParallel: Bool = true,
        validation: @escaping @Sendable (String, any Agent, AgentContext) async throws -> GuardrailResult
    ) {
        self.name = name
        self.runInParallel = runInParallel
        self.validation = validation
    }

    public func validate(
        _ input: String,
        agent: any Agent,
        context: AgentContext
    ) async throws -> GuardrailResult {
        try await validation(input, agent, context)
    }
}

/// Builder for creating input guardrails with fluent API
public struct InputGuardrailBuilder {
    private var name: String
    private var runInParallel: Bool = true
    private var validation: (@Sendable (String, any Agent, AgentContext) async throws -> GuardrailResult)?

    public init(name: String) {
        self.name = name
    }

    public func runInParallel(_ value: Bool) -> InputGuardrailBuilder {
        var copy = self
        copy.runInParallel = value
        return copy
    }

    public func validate(
        _ validation: @escaping @Sendable (String, any Agent, AgentContext) async throws -> GuardrailResult
    ) -> InputGuardrailBuilder {
        var copy = self
        copy.validation = validation
        return copy
    }

    public func build() -> ClosureInputGuardrail {
        guard let validation = validation else {
            fatalError("InputGuardrail requires a validation closure")
        }
        return ClosureInputGuardrail(
            name: name,
            runInParallel: runInParallel,
            validation: validation
        )
    }
}
```

#### File 3: `Sources/SwiftAgents/Guardrails/OutputGuardrail.swift`

```swift
import Foundation

/// Protocol for validating agent outputs after execution
public protocol OutputGuardrail: Sendable {
    /// Unique name for this guardrail
    var name: String { get }

    /// Validate the output after agent execution
    /// - Parameters:
    ///   - output: The agent's output (typically AgentResult or String)
    ///   - agent: The agent that produced the output
    ///   - context: The execution context
    /// - Returns: GuardrailResult indicating pass/fail
    func validate(
        _ output: AgentResult,
        agent: any Agent,
        context: AgentContext
    ) async throws -> GuardrailResult
}

/// Concrete output guardrail using a closure
public struct ClosureOutputGuardrail: OutputGuardrail {
    public let name: String
    private let validation: @Sendable (AgentResult, any Agent, AgentContext) async throws -> GuardrailResult

    public init(
        name: String,
        validation: @escaping @Sendable (AgentResult, any Agent, AgentContext) async throws -> GuardrailResult
    ) {
        self.name = name
        self.validation = validation
    }

    public func validate(
        _ output: AgentResult,
        agent: any Agent,
        context: AgentContext
    ) async throws -> GuardrailResult {
        try await validation(output, agent, context)
    }
}
```

#### File 4: `Sources/SwiftAgents/Guardrails/ToolGuardrails.swift`

```swift
import Foundation

/// Data passed to tool input guardrails
public struct ToolGuardrailData: Sendable {
    public let toolName: String
    public let arguments: [String: SendableValue]
    public let agent: any Agent
    public let context: AgentContext

    public init(
        toolName: String,
        arguments: [String: SendableValue],
        agent: any Agent,
        context: AgentContext
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.agent = agent
        self.context = context
    }
}

/// Data passed to tool output guardrails (extends input data with output)
public struct ToolOutputGuardrailData: Sendable {
    public let toolName: String
    public let arguments: [String: SendableValue]
    public let output: SendableValue
    public let agent: any Agent
    public let context: AgentContext

    public init(
        toolName: String,
        arguments: [String: SendableValue],
        output: SendableValue,
        agent: any Agent,
        context: AgentContext
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.output = output
        self.agent = agent
        self.context = context
    }
}

/// Protocol for validating tool inputs before execution
public protocol ToolInputGuardrail: Sendable {
    var name: String { get }
    func validate(_ data: ToolGuardrailData) async throws -> GuardrailResult
}

/// Protocol for validating tool outputs after execution
public protocol ToolOutputGuardrail: Sendable {
    var name: String { get }
    func validate(_ data: ToolOutputGuardrailData) async throws -> GuardrailResult
}

/// Concrete tool input guardrail
public struct ClosureToolInputGuardrail: ToolInputGuardrail {
    public let name: String
    private let validation: @Sendable (ToolGuardrailData) async throws -> GuardrailResult

    public init(
        name: String,
        validation: @escaping @Sendable (ToolGuardrailData) async throws -> GuardrailResult
    ) {
        self.name = name
        self.validation = validation
    }

    public func validate(_ data: ToolGuardrailData) async throws -> GuardrailResult {
        try await validation(data)
    }
}

/// Concrete tool output guardrail
public struct ClosureToolOutputGuardrail: ToolOutputGuardrail {
    public let name: String
    private let validation: @Sendable (ToolOutputGuardrailData) async throws -> GuardrailResult

    public init(
        name: String,
        validation: @escaping @Sendable (ToolOutputGuardrailData) async throws -> GuardrailResult
    ) {
        self.name = name
        self.validation = validation
    }

    public func validate(_ data: ToolOutputGuardrailData) async throws -> GuardrailResult {
        try await validation(data)
    }
}
```

#### File 5: `Sources/SwiftAgents/Guardrails/GuardrailError.swift`

```swift
import Foundation

/// Errors related to guardrail execution
public enum GuardrailError: Error, Sendable, LocalizedError {
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
```

#### File 6: `Sources/SwiftAgents/Guardrails/GuardrailRunner.swift`

```swift
import Foundation

/// Executes guardrails and handles tripwire logic
public actor GuardrailRunner {

    /// Run input guardrails
    /// - Parameters:
    ///   - guardrails: Array of input guardrails to run
    ///   - input: The user input
    ///   - agent: The agent processing the input
    ///   - context: The execution context
    /// - Throws: GuardrailError.inputTripwireTriggered if any tripwire is triggered
    public func runInputGuardrails(
        _ guardrails: [any InputGuardrail],
        input: String,
        agent: any Agent,
        context: AgentContext
    ) async throws -> [InputGuardrailResult] {
        var results: [InputGuardrailResult] = []

        // Separate parallel and sequential guardrails
        let parallelGuardrails = guardrails.filter { $0.runInParallel }
        let sequentialGuardrails = guardrails.filter { !$0.runInParallel }

        // Run sequential guardrails first (before agent starts)
        for guardrail in sequentialGuardrails {
            let result = try await runSingleInputGuardrail(
                guardrail,
                input: input,
                agent: agent,
                context: context
            )
            results.append(result)

            if result.result.tripwireTriggered {
                throw GuardrailError.inputTripwireTriggered(
                    guardrailName: guardrail.name,
                    message: result.result.message,
                    outputInfo: result.result.outputInfo
                )
            }
        }

        // Run parallel guardrails concurrently
        if !parallelGuardrails.isEmpty {
            try await withThrowingTaskGroup(of: InputGuardrailResult.self) { group in
                for guardrail in parallelGuardrails {
                    group.addTask {
                        try await self.runSingleInputGuardrail(
                            guardrail,
                            input: input,
                            agent: agent,
                            context: context
                        )
                    }
                }

                for try await result in group {
                    results.append(result)
                    if result.result.tripwireTriggered {
                        throw GuardrailError.inputTripwireTriggered(
                            guardrailName: result.guardrailName,
                            message: result.result.message,
                            outputInfo: result.result.outputInfo
                        )
                    }
                }
            }
        }

        return results
    }

    /// Run output guardrails
    public func runOutputGuardrails(
        _ guardrails: [any OutputGuardrail],
        output: AgentResult,
        agent: any Agent,
        context: AgentContext
    ) async throws -> [OutputGuardrailResult] {
        var results: [OutputGuardrailResult] = []

        for guardrail in guardrails {
            let guardrailResult = try await guardrail.validate(output, agent: agent, context: context)
            let result = OutputGuardrailResult(
                guardrailName: guardrail.name,
                agentName: agent.configuration.name ?? "Unknown",
                result: guardrailResult
            )
            results.append(result)

            if guardrailResult.tripwireTriggered {
                throw GuardrailError.outputTripwireTriggered(
                    guardrailName: guardrail.name,
                    agentName: agent.configuration.name ?? "Unknown",
                    message: guardrailResult.message,
                    outputInfo: guardrailResult.outputInfo
                )
            }
        }

        return results
    }

    /// Run tool input guardrails
    public func runToolInputGuardrails(
        _ guardrails: [any ToolInputGuardrail],
        data: ToolGuardrailData
    ) async throws -> [ToolGuardrailResult] {
        var results: [ToolGuardrailResult] = []

        for guardrail in guardrails {
            let guardrailResult = try await guardrail.validate(data)
            let result = ToolGuardrailResult(
                guardrailName: guardrail.name,
                toolName: data.toolName,
                result: guardrailResult
            )
            results.append(result)

            if guardrailResult.tripwireTriggered {
                throw GuardrailError.toolInputTripwireTriggered(
                    guardrailName: guardrail.name,
                    toolName: data.toolName,
                    message: guardrailResult.message,
                    outputInfo: guardrailResult.outputInfo
                )
            }
        }

        return results
    }

    /// Run tool output guardrails
    public func runToolOutputGuardrails(
        _ guardrails: [any ToolOutputGuardrail],
        data: ToolOutputGuardrailData
    ) async throws -> [ToolGuardrailResult] {
        var results: [ToolGuardrailResult] = []

        for guardrail in guardrails {
            let guardrailResult = try await guardrail.validate(data)
            let result = ToolGuardrailResult(
                guardrailName: guardrail.name,
                toolName: data.toolName,
                result: guardrailResult
            )
            results.append(result)

            if guardrailResult.tripwireTriggered {
                throw GuardrailError.toolOutputTripwireTriggered(
                    guardrailName: guardrail.name,
                    toolName: data.toolName,
                    message: guardrailResult.message,
                    outputInfo: guardrailResult.outputInfo
                )
            }
        }

        return results
    }

    // MARK: - Private Helpers

    private func runSingleInputGuardrail(
        _ guardrail: any InputGuardrail,
        input: String,
        agent: any Agent,
        context: AgentContext
    ) async throws -> InputGuardrailResult {
        let result = try await guardrail.validate(input, agent: agent, context: context)
        return InputGuardrailResult(
            guardrailName: guardrail.name,
            result: result
        )
    }
}

// MARK: - Result Types

public struct InputGuardrailResult: Sendable {
    public let guardrailName: String
    public let result: GuardrailResult
}

public struct OutputGuardrailResult: Sendable {
    public let guardrailName: String
    public let agentName: String
    public let result: GuardrailResult
}

public struct ToolGuardrailResult: Sendable {
    public let guardrailName: String
    public let toolName: String
    public let result: GuardrailResult
}
```

#### Integration: Update `Agent` Protocol

In `Sources/SwiftAgents/Core/Agent.swift`, add:

```swift
public protocol Agent: Sendable {
    // ... existing properties ...

    /// Input guardrails to validate input before execution
    nonisolated var inputGuardrails: [any InputGuardrail] { get }

    /// Output guardrails to validate output after execution
    nonisolated var outputGuardrails: [any OutputGuardrail] { get }
}

// Default implementations
public extension Agent {
    nonisolated var inputGuardrails: [any InputGuardrail] { [] }
    nonisolated var outputGuardrails: [any OutputGuardrail] { [] }
}
```

#### Integration: Update `Tool` Protocol

In `Sources/SwiftAgents/Tools/Tool.swift`, add:

```swift
public protocol Tool: Sendable {
    // ... existing properties ...

    /// Input guardrails to validate arguments before execution
    var inputGuardrails: [any ToolInputGuardrail] { get }

    /// Output guardrails to validate result after execution
    var outputGuardrails: [any ToolOutputGuardrail] { get }
}

// Default implementations
public extension Tool {
    var inputGuardrails: [any ToolInputGuardrail] { [] }
    var outputGuardrails: [any ToolOutputGuardrail] { [] }
}
```

#### Integration: Update `ToolRegistry`

In `Sources/SwiftAgents/Tools/Tool.swift`, update `ToolRegistry.execute()`:

```swift
public func execute(
    toolNamed name: String,
    arguments: [String: SendableValue],
    agent: any Agent,
    context: AgentContext
) async throws -> SendableValue {
    guard let tool = tools[name] else {
        throw AgentError.toolNotFound(name: name)
    }

    let guardrailRunner = GuardrailRunner()

    // Run input guardrails
    if !tool.inputGuardrails.isEmpty {
        let data = ToolGuardrailData(
            toolName: name,
            arguments: arguments,
            agent: agent,
            context: context
        )
        _ = try await guardrailRunner.runToolInputGuardrails(tool.inputGuardrails, data: data)
    }

    // Execute tool
    let result = try await tool.execute(arguments: arguments)

    // Run output guardrails
    if !tool.outputGuardrails.isEmpty {
        let data = ToolOutputGuardrailData(
            toolName: name,
            arguments: arguments,
            output: result,
            agent: agent,
            context: context
        )
        _ = try await guardrailRunner.runToolOutputGuardrails(tool.outputGuardrails, data: data)
    }

    return result
}
```

---

## Phase 2: Streaming Events & RunHooks

### Overview
Implement rich streaming events during execution and lifecycle hooks for custom integrations.

### OpenAI Reference Implementation

```python
# OpenAI's RunItemStreamEvent
@dataclass
class RunItemStreamEvent:
    name: Literal[
        "message_output_created",
        "handoff_requested",
        "handoff_occured",
        "tool_called",
        "tool_output",
        "reasoning_item_created",
    ]
    item: RunItem
    type: Literal["run_item_stream_event"] = "run_item_stream_event"

# OpenAI's RunHooksBase
class RunHooksBase[TContext, TAgent]:
    async def on_agent_start(self, context, agent) -> None
    async def on_agent_end(self, context, agent, output) -> None
    async def on_handoff(self, context, from_agent, to_agent) -> None
    async def on_tool_start(self, context, agent, tool) -> None
    async def on_tool_end(self, context, agent, tool, result) -> None
    async def on_llm_start(self, context, agent, system_prompt, input_items) -> None
    async def on_llm_end(self, context, agent, response) -> None
```

### SwiftAgents Implementation

#### File 1: Update `Sources/SwiftAgents/Core/AgentEvent.swift`

```swift
import Foundation

/// Events emitted during agent execution
public enum AgentEvent: Sendable {
    // MARK: - Lifecycle Events

    /// Agent execution started
    case started(input: String, agentName: String)

    /// Agent execution completed successfully
    case completed(result: AgentResult)

    /// Agent execution failed with error
    case failed(error: Error)

    /// Agent execution was cancelled
    case cancelled

    // MARK: - Reasoning Events (NEW)

    /// Agent is thinking/reasoning
    case thinking(thought: String, iteration: Int)

    /// Agent made a decision
    case decision(decision: String, options: [String]?)

    /// Agent created or updated a plan
    case planUpdated(plan: String, stepCount: Int)

    // MARK: - Tool Events (NEW)

    /// Tool execution started
    case toolCallStarted(
        toolName: String,
        arguments: [String: SendableValue],
        spanId: UUID
    )

    /// Tool execution completed
    case toolCallCompleted(
        toolName: String,
        result: SendableValue,
        duration: TimeInterval,
        spanId: UUID
    )

    /// Tool execution failed
    case toolCallFailed(
        toolName: String,
        error: Error,
        spanId: UUID
    )

    // MARK: - Iteration Events (NEW)

    /// Iteration started
    case iterationStarted(iteration: Int, maxIterations: Int)

    /// Iteration completed
    case iterationCompleted(iteration: Int, hasMoreWork: Bool)

    // MARK: - Output Events (NEW)

    /// Streaming output token (for real-time display)
    case outputToken(token: String)

    /// Streaming output chunk (larger piece)
    case outputChunk(chunk: String)

    // MARK: - Handoff Events (NEW)

    /// Agent handoff initiated
    case handoffRequested(
        fromAgent: String,
        toAgent: String,
        reason: String?
    )

    /// Agent handoff completed
    case handoffCompleted(
        fromAgent: String,
        toAgent: String
    )

    // MARK: - Guardrail Events (NEW)

    /// Guardrail check started
    case guardrailStarted(name: String, type: GuardrailType)

    /// Guardrail check passed
    case guardrailPassed(name: String, type: GuardrailType)

    /// Guardrail tripwire triggered
    case guardrailTriggered(
        name: String,
        type: GuardrailType,
        message: String?
    )

    // MARK: - Memory Events (NEW)

    /// Memory was accessed
    case memoryAccessed(operation: MemoryOperation, count: Int)

    // MARK: - LLM Events (NEW)

    /// LLM call started
    case llmStarted(model: String?, promptTokens: Int?)

    /// LLM call completed
    case llmCompleted(
        model: String?,
        promptTokens: Int?,
        completionTokens: Int?,
        duration: TimeInterval
    )
}

// MARK: - Supporting Types

public enum GuardrailType: String, Sendable {
    case input
    case output
    case toolInput
    case toolOutput
}

public enum MemoryOperation: String, Sendable {
    case read
    case write
    case search
    case clear
}
```

#### File 2: `Sources/SwiftAgents/Core/RunHooks.swift`

```swift
import Foundation

/// Protocol for receiving callbacks during agent run lifecycle
public protocol RunHooks: Sendable {
    /// Called when an agent starts execution
    func onAgentStart(
        context: AgentContext,
        agent: any Agent,
        input: String
    ) async

    /// Called when an agent completes execution
    func onAgentEnd(
        context: AgentContext,
        agent: any Agent,
        result: AgentResult
    ) async

    /// Called when an error occurs
    func onError(
        context: AgentContext,
        agent: any Agent,
        error: Error
    ) async

    /// Called when a handoff occurs between agents
    func onHandoff(
        context: AgentContext,
        fromAgent: any Agent,
        toAgent: any Agent
    ) async

    /// Called when a tool starts execution
    func onToolStart(
        context: AgentContext,
        agent: any Agent,
        tool: any Tool,
        arguments: [String: SendableValue]
    ) async

    /// Called when a tool completes execution
    func onToolEnd(
        context: AgentContext,
        agent: any Agent,
        tool: any Tool,
        result: SendableValue
    ) async

    /// Called when LLM inference starts
    func onLLMStart(
        context: AgentContext,
        agent: any Agent,
        systemPrompt: String?,
        inputMessages: [MemoryMessage]
    ) async

    /// Called when LLM inference completes
    func onLLMEnd(
        context: AgentContext,
        agent: any Agent,
        response: String,
        usage: TokenUsage?
    ) async

    /// Called when a guardrail is triggered
    func onGuardrailTriggered(
        context: AgentContext,
        guardrailName: String,
        guardrailType: GuardrailType,
        result: GuardrailResult
    ) async
}

// MARK: - Default Implementations

public extension RunHooks {
    func onAgentStart(context: AgentContext, agent: any Agent, input: String) async {}
    func onAgentEnd(context: AgentContext, agent: any Agent, result: AgentResult) async {}
    func onError(context: AgentContext, agent: any Agent, error: Error) async {}
    func onHandoff(context: AgentContext, fromAgent: any Agent, toAgent: any Agent) async {}
    func onToolStart(context: AgentContext, agent: any Agent, tool: any Tool, arguments: [String: SendableValue]) async {}
    func onToolEnd(context: AgentContext, agent: any Agent, tool: any Tool, result: SendableValue) async {}
    func onLLMStart(context: AgentContext, agent: any Agent, systemPrompt: String?, inputMessages: [MemoryMessage]) async {}
    func onLLMEnd(context: AgentContext, agent: any Agent, response: String, usage: TokenUsage?) async {}
    func onGuardrailTriggered(context: AgentContext, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async {}
}

// MARK: - Token Usage

public struct TokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = promptTokens + completionTokens
    }
}

// MARK: - Composite Hooks

/// Runs multiple hooks in sequence
public struct CompositeRunHooks: RunHooks {
    private let hooks: [any RunHooks]

    public init(_ hooks: [any RunHooks]) {
        self.hooks = hooks
    }

    public func onAgentStart(context: AgentContext, agent: any Agent, input: String) async {
        for hook in hooks {
            await hook.onAgentStart(context: context, agent: agent, input: input)
        }
    }

    public func onAgentEnd(context: AgentContext, agent: any Agent, result: AgentResult) async {
        for hook in hooks {
            await hook.onAgentEnd(context: context, agent: agent, result: result)
        }
    }

    public func onError(context: AgentContext, agent: any Agent, error: Error) async {
        for hook in hooks {
            await hook.onError(context: context, agent: agent, error: error)
        }
    }

    public func onHandoff(context: AgentContext, fromAgent: any Agent, toAgent: any Agent) async {
        for hook in hooks {
            await hook.onHandoff(context: context, fromAgent: fromAgent, toAgent: toAgent)
        }
    }

    public func onToolStart(context: AgentContext, agent: any Agent, tool: any Tool, arguments: [String: SendableValue]) async {
        for hook in hooks {
            await hook.onToolStart(context: context, agent: agent, tool: tool, arguments: arguments)
        }
    }

    public func onToolEnd(context: AgentContext, agent: any Agent, tool: any Tool, result: SendableValue) async {
        for hook in hooks {
            await hook.onToolEnd(context: context, agent: agent, tool: tool, result: result)
        }
    }

    public func onLLMStart(context: AgentContext, agent: any Agent, systemPrompt: String?, inputMessages: [MemoryMessage]) async {
        for hook in hooks {
            await hook.onLLMStart(context: context, agent: agent, systemPrompt: systemPrompt, inputMessages: inputMessages)
        }
    }

    public func onLLMEnd(context: AgentContext, agent: any Agent, response: String, usage: TokenUsage?) async {
        for hook in hooks {
            await hook.onLLMEnd(context: context, agent: agent, response: response, usage: usage)
        }
    }

    public func onGuardrailTriggered(context: AgentContext, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async {
        for hook in hooks {
            await hook.onGuardrailTriggered(context: context, guardrailName: guardrailName, guardrailType: guardrailType, result: result)
        }
    }
}

// MARK: - Logging Hooks

/// Hook that logs all events
public struct LoggingRunHooks: RunHooks {
    private let logger: Logger

    public init(logger: Logger = Log.agents) {
        self.logger = logger
    }

    public func onAgentStart(context: AgentContext, agent: any Agent, input: String) async {
        logger.info("Agent '\(agent.configuration.name ?? "Unknown")' started with input: \(input.prefix(100))...")
    }

    public func onAgentEnd(context: AgentContext, agent: any Agent, result: AgentResult) async {
        logger.info("Agent '\(agent.configuration.name ?? "Unknown")' completed with output: \(result.output.prefix(100))...")
    }

    public func onError(context: AgentContext, agent: any Agent, error: Error) async {
        logger.error("Agent '\(agent.configuration.name ?? "Unknown")' error: \(error.localizedDescription)")
    }

    public func onHandoff(context: AgentContext, fromAgent: any Agent, toAgent: any Agent) async {
        logger.info("Handoff from '\(fromAgent.configuration.name ?? "Unknown")' to '\(toAgent.configuration.name ?? "Unknown")'")
    }

    public func onToolStart(context: AgentContext, agent: any Agent, tool: any Tool, arguments: [String: SendableValue]) async {
        logger.debug("Tool '\(tool.name)' started with \(arguments.count) arguments")
    }

    public func onToolEnd(context: AgentContext, agent: any Agent, tool: any Tool, result: SendableValue) async {
        logger.debug("Tool '\(tool.name)' completed")
    }

    public func onGuardrailTriggered(context: AgentContext, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async {
        logger.warning("Guardrail '\(guardrailName)' (\(guardrailType.rawValue)) triggered: \(result.message ?? "No message")")
    }
}
```

#### Integration: Update Agent `run()` Methods

In agent implementations (e.g., `ReActAgent.swift`), add hooks parameter and emit events:

```swift
public func run(
    _ input: String,
    context: AgentContext? = nil,
    hooks: (any RunHooks)? = nil
) async throws -> AgentResult {
    let ctx = context ?? AgentContext()

    // Emit start event
    await emitEvent(.started(input: input, agentName: configuration.name ?? "Unknown"))
    await hooks?.onAgentStart(context: ctx, agent: self, input: input)

    do {
        // Run input guardrails
        if !inputGuardrails.isEmpty {
            for guardrail in inputGuardrails {
                await emitEvent(.guardrailStarted(name: guardrail.name, type: .input))
            }
            let guardrailRunner = GuardrailRunner()
            _ = try await guardrailRunner.runInputGuardrails(
                inputGuardrails,
                input: input,
                agent: self,
                context: ctx
            )
            for guardrail in inputGuardrails {
                await emitEvent(.guardrailPassed(name: guardrail.name, type: .input))
            }
        }

        // ... existing execution logic ...
        // Add event emissions at appropriate points

        let result = try await executeLoop(input: input, context: ctx, hooks: hooks)

        // Run output guardrails
        if !outputGuardrails.isEmpty {
            let guardrailRunner = GuardrailRunner()
            _ = try await guardrailRunner.runOutputGuardrails(
                outputGuardrails,
                output: result,
                agent: self,
                context: ctx
            )
        }

        await emitEvent(.completed(result: result))
        await hooks?.onAgentEnd(context: ctx, agent: self, result: result)

        return result

    } catch let error as GuardrailError {
        await hooks?.onError(context: ctx, agent: self, error: error)
        await emitEvent(.failed(error: error))
        throw error
    } catch {
        await hooks?.onError(context: ctx, agent: self, error: error)
        await emitEvent(.failed(error: error))
        throw error
    }
}
```

---

## Phase 3: Session & TraceContext

### Overview
Implement Session protocol for automatic conversation history management and TraceContext for grouping related traces.

### OpenAI Reference Implementation

```python
# OpenAI's Session Protocol
class Session(Protocol):
    session_id: str

    async def get_items(self, limit: int | None = None) -> list[TResponseInputItem]:
        """Retrieve conversation history."""
        ...

    async def add_items(self, items: list[TResponseInputItem]) -> None:
        """Add items to history."""
        ...

    async def pop_item(self) -> TResponseInputItem | None:
        """Remove and return most recent item."""
        ...

    async def clear_session(self) -> None:
        """Clear all items."""
        ...

# OpenAI's trace context manager
with trace("Customer Service", group_id="chat_123", metadata={"customer": "user_456"}):
    result1 = await Runner.run(agent, query1)
    result2 = await Runner.run(agent, query2)
```

### SwiftAgents Implementation

#### File 1: `Sources/SwiftAgents/Memory/Session.swift`

```swift
import Foundation

/// Protocol for managing conversation session history
/// Provides automatic conversation history management for agents
public protocol Session: Actor, Sendable {
    /// Unique identifier for this session
    var sessionId: String { get }

    /// Retrieve conversation history
    /// - Parameter limit: Maximum items to retrieve (nil = all)
    /// - Returns: Array of messages in chronological order
    func getItems(limit: Int?) async throws -> [MemoryMessage]

    /// Add items to conversation history
    func addItems(_ items: [MemoryMessage]) async throws

    /// Remove and return the most recent item
    func popItem() async throws -> MemoryMessage?

    /// Clear all items in this session
    func clearSession() async throws

    /// Get the total count of items
    var itemCount: Int { get async }
}

// MARK: - Default Implementations

public extension Session {
    /// Add a single item
    func addItem(_ item: MemoryMessage) async throws {
        try await addItems([item])
    }

    /// Get all items (no limit)
    func getAllItems() async throws -> [MemoryMessage] {
        try await getItems(limit: nil)
    }
}
```

#### File 2: `Sources/SwiftAgents/Memory/InMemorySession.swift`

```swift
import Foundation

/// In-memory session implementation for testing and simple use cases
public actor InMemorySession: Session {
    public let sessionId: String
    private var items: [MemoryMessage] = []

    public init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId
    }

    public var itemCount: Int {
        items.count
    }

    public func getItems(limit: Int?) async throws -> [MemoryMessage] {
        if let limit = limit {
            let startIndex = max(0, items.count - limit)
            return Array(items[startIndex...])
        }
        return items
    }

    public func addItems(_ newItems: [MemoryMessage]) async throws {
        items.append(contentsOf: newItems)
    }

    public func popItem() async throws -> MemoryMessage? {
        guard !items.isEmpty else { return nil }
        return items.removeLast()
    }

    public func clearSession() async throws {
        items.removeAll()
    }
}
```

#### File 3: `Sources/SwiftAgents/Memory/PersistentSession.swift`

```swift
import Foundation
import SwiftData

/// SwiftData-backed persistent session
@available(iOS 17.0, macOS 14.0, *)
public actor PersistentSession: Session {
    public let sessionId: String
    private let backend: SwiftDataBackend

    public init(sessionId: String, backend: SwiftDataBackend) {
        self.sessionId = sessionId
        self.backend = backend
    }

    /// Create with default persistent storage
    public static func persistent(sessionId: String) throws -> PersistentSession {
        let backend = try SwiftDataBackend.persistent()
        return PersistentSession(sessionId: sessionId, backend: backend)
    }

    /// Create with in-memory storage (for testing)
    public static func inMemory(sessionId: String) throws -> PersistentSession {
        let backend = try SwiftDataBackend.inMemory()
        return PersistentSession(sessionId: sessionId, backend: backend)
    }

    public var itemCount: Int {
        get async {
            (try? await backend.messageCount(conversationId: sessionId)) ?? 0
        }
    }

    public func getItems(limit: Int?) async throws -> [MemoryMessage] {
        if let limit = limit {
            return try await backend.fetchRecentMessages(conversationId: sessionId, limit: limit)
        }
        return try await backend.fetchMessages(conversationId: sessionId)
    }

    public func addItems(_ items: [MemoryMessage]) async throws {
        try await backend.storeAll(items, conversationId: sessionId)
    }

    public func popItem() async throws -> MemoryMessage? {
        let items = try await backend.fetchRecentMessages(conversationId: sessionId, limit: 1)
        if let last = items.last {
            try await backend.deleteOldestMessages(conversationId: sessionId, keepRecent: await itemCount - 1)
            return last
        }
        return nil
    }

    public func clearSession() async throws {
        try await backend.deleteMessages(conversationId: sessionId)
    }
}
```

#### File 4: `Sources/SwiftAgents/Observability/TraceContext.swift`

```swift
import Foundation

/// Context for grouping related traces together
public actor TraceContext {
    /// Name of this trace workflow
    public let name: String

    /// Unique trace identifier
    public let traceId: UUID

    /// Group identifier for linking related traces
    public let groupId: String?

    /// Additional metadata
    public let metadata: [String: SendableValue]

    /// Start time of the trace
    public let startTime: Date

    /// Child spans in this trace
    private var spans: [TraceSpan] = []

    private init(
        name: String,
        traceId: UUID = UUID(),
        groupId: String? = nil,
        metadata: [String: SendableValue] = [:]
    ) {
        self.name = name
        self.traceId = traceId
        self.groupId = groupId
        self.metadata = metadata
        self.startTime = Date()
    }

    /// Execute an operation within a trace context
    /// - Parameters:
    ///   - name: Name of the workflow/trace
    ///   - groupId: Optional group ID to link related traces
    ///   - metadata: Additional metadata to attach
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    public static func withTrace<T: Sendable>(
        _ name: String,
        groupId: String? = nil,
        metadata: [String: SendableValue] = [:],
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        let context = TraceContext(name: name, groupId: groupId, metadata: metadata)

        // Store in task-local storage
        return try await TraceContextStorage.$current.withValue(context) {
            try await operation()
        }
    }

    /// Get the current trace context (if any)
    public static var current: TraceContext? {
        TraceContextStorage.current
    }

    /// Add a span to this trace
    public func addSpan(_ span: TraceSpan) {
        spans.append(span)
    }

    /// Get all spans in this trace
    public func getSpans() -> [TraceSpan] {
        spans
    }

    /// Calculate total duration
    public var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

// MARK: - Task-Local Storage

private enum TraceContextStorage {
    @TaskLocal
    static var current: TraceContext?
}

// MARK: - Trace Span

public struct TraceSpan: Sendable {
    public let spanId: UUID
    public let parentSpanId: UUID?
    public let name: String
    public let startTime: Date
    public let endTime: Date?
    public let status: SpanStatus
    public let metadata: [String: SendableValue]

    public init(
        spanId: UUID = UUID(),
        parentSpanId: UUID? = nil,
        name: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        status: SpanStatus = .ok,
        metadata: [String: SendableValue] = [:]
    ) {
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.metadata = metadata
    }

    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
}

public enum SpanStatus: String, Sendable {
    case ok
    case error
    case cancelled
}

// MARK: - Convenience Extensions

public extension TraceContext {
    /// Create a new span within this trace
    func span(
        _ name: String,
        parentSpanId: UUID? = nil,
        metadata: [String: SendableValue] = [:]
    ) -> TraceSpan {
        TraceSpan(
            parentSpanId: parentSpanId,
            name: name,
            metadata: metadata
        )
    }
}

// MARK: - Integration with TracingHelper

public extension TracingHelper {
    /// Get the current trace context's traceId
    var currentTraceId: UUID? {
        TraceContext.current?.traceId
    }

    /// Get the current trace context's groupId
    var currentGroupId: String? {
        TraceContext.current?.groupId
    }
}
```

---

## Phase 4: Enhanced Handoffs & MultiProvider

### Overview
Implement enhanced handoff callbacks and multi-provider model routing.

### OpenAI Reference Implementation

```python
# OpenAI's handoff function
def handoff(
    agent: Agent[TContext],
    *,
    on_handoff: OnHandoffWithInput[THandoffInput] | OnHandoffWithoutInput | None = None,
    input_type: type[THandoffInput] | None = None,
    tool_description_override: str | None = None,
    tool_name_override: str | None = None,
    input_filter: Callable[[HandoffInputData], HandoffInputData] | None = None,
    nest_handoff_history: bool | None = None,
    is_enabled: bool | Callable[[RunContextWrapper[Any], Agent[Any]], MaybeAwaitable[bool]] = True,
) -> Handoff[TContext, Agent[TContext]]

# OpenAI's MultiProvider
class MultiProvider(ModelProvider):
    # "openai/" prefix or no prefix -> OpenAIProvider
    # "litellm/" prefix -> LitellmProvider
    def get_model(self, model_name: str | None) -> Model
```

### SwiftAgents Implementation

#### File 1: Update `Sources/SwiftAgents/Orchestration/Handoff.swift`

```swift
import Foundation

/// Configuration for agent handoffs
public struct HandoffConfiguration: Sendable {
    /// The target agent to hand off to
    public let targetAgent: any Agent

    /// Callback when handoff is invoked
    public let onHandoff: (@Sendable (AgentContext, HandoffInputData) async throws -> Void)?

    /// Filter/transform input data before handoff
    public let inputFilter: (@Sendable (HandoffInputData) -> HandoffInputData)?

    /// Override the tool name used for this handoff
    public let toolNameOverride: String?

    /// Override the tool description
    public let toolDescriptionOverride: String?

    /// Whether to nest the previous agent's history
    public let nestHandoffHistory: Bool

    /// Dynamic enablement check
    public let isEnabled: (@Sendable (AgentContext, any Agent) async -> Bool)?

    public init(
        targetAgent: any Agent,
        onHandoff: (@Sendable (AgentContext, HandoffInputData) async throws -> Void)? = nil,
        inputFilter: (@Sendable (HandoffInputData) -> HandoffInputData)? = nil,
        toolNameOverride: String? = nil,
        toolDescriptionOverride: String? = nil,
        nestHandoffHistory: Bool = false,
        isEnabled: (@Sendable (AgentContext, any Agent) async -> Bool)? = nil
    ) {
        self.targetAgent = targetAgent
        self.onHandoff = onHandoff
        self.inputFilter = inputFilter
        self.toolNameOverride = toolNameOverride
        self.toolDescriptionOverride = toolDescriptionOverride
        self.nestHandoffHistory = nestHandoffHistory
        self.isEnabled = isEnabled
    }

    /// Resolved tool name
    public var toolName: String {
        toolNameOverride ?? "handoff_to_\(targetAgent.configuration.name ?? "agent")"
    }

    /// Resolved tool description
    public var toolDescription: String {
        toolDescriptionOverride ?? "Hand off to \(targetAgent.configuration.name ?? "another agent")"
    }
}

/// Data passed during handoff
public struct HandoffInputData: Sendable {
    public var input: String
    public var history: [MemoryMessage]
    public var metadata: [String: SendableValue]
    public var sourceAgentName: String

    public init(
        input: String,
        history: [MemoryMessage] = [],
        metadata: [String: SendableValue] = [:],
        sourceAgentName: String
    ) {
        self.input = input
        self.history = history
        self.metadata = metadata
        self.sourceAgentName = sourceAgentName
    }
}

/// Event emitted when a handoff occurs
public struct HandoffEvent: Sendable {
    public let fromAgent: String
    public let toAgent: String
    public let input: String
    public let timestamp: Date
    public let metadata: [String: SendableValue]

    public init(
        fromAgent: String,
        toAgent: String,
        input: String,
        timestamp: Date = Date(),
        metadata: [String: SendableValue] = [:]
    ) {
        self.fromAgent = fromAgent
        self.toAgent = toAgent
        self.input = input
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

/// Builder for creating handoff configurations
public struct HandoffBuilder {
    private var targetAgent: (any Agent)?
    private var onHandoff: (@Sendable (AgentContext, HandoffInputData) async throws -> Void)?
    private var inputFilter: (@Sendable (HandoffInputData) -> HandoffInputData)?
    private var toolNameOverride: String?
    private var toolDescriptionOverride: String?
    private var nestHandoffHistory: Bool = false
    private var isEnabled: (@Sendable (AgentContext, any Agent) async -> Bool)?

    public init() {}

    public func target(_ agent: any Agent) -> HandoffBuilder {
        var copy = self
        copy.targetAgent = agent
        return copy
    }

    public func onHandoff(
        _ callback: @escaping @Sendable (AgentContext, HandoffInputData) async throws -> Void
    ) -> HandoffBuilder {
        var copy = self
        copy.onHandoff = callback
        return copy
    }

    public func inputFilter(
        _ filter: @escaping @Sendable (HandoffInputData) -> HandoffInputData
    ) -> HandoffBuilder {
        var copy = self
        copy.inputFilter = filter
        return copy
    }

    public func toolName(_ name: String) -> HandoffBuilder {
        var copy = self
        copy.toolNameOverride = name
        return copy
    }

    public func toolDescription(_ description: String) -> HandoffBuilder {
        var copy = self
        copy.toolDescriptionOverride = description
        return copy
    }

    public func nestHistory(_ nest: Bool) -> HandoffBuilder {
        var copy = self
        copy.nestHandoffHistory = nest
        return copy
    }

    public func isEnabled(
        _ check: @escaping @Sendable (AgentContext, any Agent) async -> Bool
    ) -> HandoffBuilder {
        var copy = self
        copy.isEnabled = check
        return copy
    }

    public func build() -> HandoffConfiguration {
        guard let target = targetAgent else {
            fatalError("HandoffBuilder requires a target agent")
        }
        return HandoffConfiguration(
            targetAgent: target,
            onHandoff: onHandoff,
            inputFilter: inputFilter,
            toolNameOverride: toolNameOverride,
            toolDescriptionOverride: toolDescriptionOverride,
            nestHandoffHistory: nestHandoffHistory,
            isEnabled: isEnabled
        )
    }
}

/// Convenience function for creating handoffs (matches OpenAI's API)
public func handoff(
    to agent: any Agent,
    onHandoff: (@Sendable (AgentContext, HandoffInputData) async throws -> Void)? = nil,
    inputFilter: (@Sendable (HandoffInputData) -> HandoffInputData)? = nil,
    toolNameOverride: String? = nil,
    toolDescriptionOverride: String? = nil,
    nestHandoffHistory: Bool = false,
    isEnabled: (@Sendable (AgentContext, any Agent) async -> Bool)? = nil
) -> HandoffConfiguration {
    HandoffConfiguration(
        targetAgent: agent,
        onHandoff: onHandoff,
        inputFilter: inputFilter,
        toolNameOverride: toolNameOverride,
        toolDescriptionOverride: toolDescriptionOverride,
        nestHandoffHistory: nestHandoffHistory,
        isEnabled: isEnabled
    )
}
```

#### File 2: `Sources/SwiftAgents/Providers/MultiProvider.swift`

```swift
import Foundation

/// Multi-provider that routes model names to appropriate providers based on prefix
public actor MultiProvider: InferenceProvider {
    /// Registered providers by prefix
    private var providerMap: [String: any InferenceProvider] = [:]

    /// Default provider when no prefix matches
    private let defaultProvider: any InferenceProvider

    /// Initialize with a default provider
    public init(defaultProvider: any InferenceProvider) {
        self.defaultProvider = defaultProvider
    }

    /// Register a provider for a prefix
    /// - Parameters:
    ///   - prefix: The prefix to match (e.g., "anthropic", "openai")
    ///   - provider: The provider to use for this prefix
    public func register(prefix: String, provider: any InferenceProvider) {
        providerMap[prefix.lowercased()] = provider
    }

    /// Remove a registered provider
    public func unregister(prefix: String) {
        providerMap.removeValue(forKey: prefix.lowercased())
    }

    /// Get all registered prefixes
    public var registeredPrefixes: [String] {
        Array(providerMap.keys)
    }

    // MARK: - InferenceProvider Conformance

    public func generate(
        prompt: String,
        systemPrompt: String?,
        model: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> String {
        let (provider, resolvedModel) = resolveProvider(for: model)
        return try await provider.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: resolvedModel,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    public func generateWithToolCalls(
        messages: [MemoryMessage],
        tools: [ToolDefinition],
        model: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> InferenceResponse {
        let (provider, resolvedModel) = resolveProvider(for: model)
        return try await provider.generateWithToolCalls(
            messages: messages,
            tools: tools,
            model: resolvedModel,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    public func stream(
        prompt: String,
        systemPrompt: String?,
        model: String?,
        temperature: Double?,
        maxTokens: Int?
    ) -> AsyncThrowingStream<String, Error> {
        // Note: This is synchronous resolution, stream is returned
        let (provider, resolvedModel) = resolveProviderSync(for: model)
        return provider.stream(
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: resolvedModel,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    // MARK: - Private Helpers

    /// Parse model name into prefix and model
    private func parseModelName(_ modelName: String?) -> (prefix: String?, model: String?) {
        guard let modelName = modelName else {
            return (nil, nil)
        }

        if modelName.contains("/") {
            let parts = modelName.split(separator: "/", maxSplits: 1)
            if parts.count == 2 {
                return (String(parts[0]).lowercased(), String(parts[1]))
            }
        }

        return (nil, modelName)
    }

    /// Resolve provider for a model name
    private func resolveProvider(for model: String?) -> (any InferenceProvider, String?) {
        let (prefix, resolvedModel) = parseModelName(model)

        if let prefix = prefix, let provider = providerMap[prefix] {
            return (provider, resolvedModel)
        }

        return (defaultProvider, resolvedModel ?? model)
    }

    /// Synchronous version for stream (providers are already registered)
    private nonisolated func resolveProviderSync(for model: String?) -> (any InferenceProvider, String?) {
        // For streaming, we need synchronous access
        // This is a simplified version - in production, consider caching
        let (prefix, resolvedModel) = parseModelNameSync(model)

        // Return default for now - proper implementation would need actor isolation handling
        return (defaultProvider, resolvedModel ?? model)
    }

    private nonisolated func parseModelNameSync(_ modelName: String?) -> (prefix: String?, model: String?) {
        guard let modelName = modelName else {
            return (nil, nil)
        }

        if modelName.contains("/") {
            let parts = modelName.split(separator: "/", maxSplits: 1)
            if parts.count == 2 {
                return (String(parts[0]).lowercased(), String(parts[1]))
            }
        }

        return (nil, modelName)
    }
}

// MARK: - Convenience Initializers

public extension MultiProvider {
    /// Create with OpenRouter as default
    static func withOpenRouter(apiKey: String) -> MultiProvider {
        let openRouter = OpenRouterProvider(apiKey: apiKey)
        return MultiProvider(defaultProvider: openRouter)
    }
}
```

---

## Phase 5: Polish Features

### File 1: Add Parallel Tool Calls to `AgentConfiguration`

```swift
// In Sources/SwiftAgents/Core/AgentConfiguration.swift

public struct AgentConfiguration: Sendable {
    // ... existing properties ...

    /// Whether to execute multiple tool calls in parallel
    public var parallelToolCalls: Bool = false

    /// Previous response ID for conversation continuation
    public var previousResponseId: String?

    /// Whether to auto-populate previous response ID
    public var autoPreviousResponseId: Bool = false
}
```

### File 2: Update Tool Execution for Parallel Calls

```swift
// In ToolCallingAgent or ToolRegistry

/// Execute multiple tools in parallel
public func executeToolsInParallel(
    calls: [(name: String, arguments: [String: SendableValue])],
    agent: any Agent,
    context: AgentContext
) async throws -> [(name: String, result: SendableValue)] {
    try await withThrowingTaskGroup(of: (String, SendableValue).self) { group in
        for call in calls {
            group.addTask {
                let result = try await self.execute(
                    toolNamed: call.name,
                    arguments: call.arguments,
                    agent: agent,
                    context: context
                )
                return (call.name, result)
            }
        }

        var results: [(String, SendableValue)] = []
        for try await result in group {
            results.append(result)
        }
        return results
    }
}
```

---

## Phase 6: Future Enhancements

### MCP Integration (Model Context Protocol)

```swift
// Sources/SwiftAgents/MCP/MCPServer.swift

/// Protocol for MCP server integration
public protocol MCPServer: Sendable {
    var name: String { get }
    var capabilities: MCPCapabilities { get }

    func listTools() async throws -> [ToolDefinition]
    func callTool(name: String, arguments: [String: SendableValue]) async throws -> SendableValue
    func listResources() async throws -> [MCPResource]
    func readResource(uri: String) async throws -> MCPResourceContent
}

public struct MCPCapabilities: Sendable {
    public let tools: Bool
    public let resources: Bool
    public let prompts: Bool
}

public struct MCPResource: Sendable {
    public let uri: String
    public let name: String
    public let mimeType: String?
}

public struct MCPResourceContent: Sendable {
    public let uri: String
    public let mimeType: String?
    public let text: String?
    public let blob: Data?
}
```

### Extended Model Settings

```swift
// Sources/SwiftAgents/Core/ModelSettings.swift

/// Comprehensive model configuration settings
public struct ModelSettings: Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var maxTokens: Int?
    public var frequencyPenalty: Double?
    public var presencePenalty: Double?
    public var stopSequences: [String]?
    public var seed: Int?

    /// Tool selection strategy
    public var toolChoice: ToolChoice?

    /// Whether to allow parallel tool calls
    public var parallelToolCalls: Bool?

    /// Truncation strategy
    public var truncation: TruncationStrategy?

    /// Response verbosity level
    public var verbosity: Verbosity?

    /// Prompt cache retention
    public var promptCacheRetention: CacheRetention?

    public init() {}
}

public enum ToolChoice: Sendable {
    case auto
    case none
    case required
    case specific(toolName: String)
}

public enum TruncationStrategy: String, Sendable {
    case auto
    case disabled
}

public enum Verbosity: String, Sendable {
    case low
    case medium
    case high
}

public enum CacheRetention: String, Sendable {
    case inMemory = "in_memory"
    case twentyFourHours = "24h"
}
```

---

## Testing Strategy

### Unit Test Template

```swift
import XCTest
@testable import SwiftAgents

final class GuardrailTests: XCTestCase {

    func testInputGuardrailPasses() async throws {
        let guardrail = ClosureInputGuardrail(name: "test") { input, _, _ in
            .pass()
        }

        let mockAgent = MockAgent()
        let context = AgentContext()

        let result = try await guardrail.validate("Hello", agent: mockAgent, context: context)
        XCTAssertFalse(result.tripwireTriggered)
    }

    func testInputGuardrailTriggered() async throws {
        let guardrail = ClosureInputGuardrail(name: "blocker") { input, _, _ in
            if input.contains("blocked") {
                return .fail(message: "Blocked content detected")
            }
            return .pass()
        }

        let mockAgent = MockAgent()
        let context = AgentContext()

        let result = try await guardrail.validate("This is blocked content", agent: mockAgent, context: context)
        XCTAssertTrue(result.tripwireTriggered)
        XCTAssertEqual(result.message, "Blocked content detected")
    }

    func testGuardrailRunnerThrowsOnTripwire() async {
        let guardrail = ClosureInputGuardrail(name: "blocker") { _, _, _ in
            .fail(message: "Always fails")
        }

        let runner = GuardrailRunner()
        let mockAgent = MockAgent()
        let context = AgentContext()

        do {
            _ = try await runner.runInputGuardrails(
                [guardrail],
                input: "test",
                agent: mockAgent,
                context: context
            )
            XCTFail("Should have thrown")
        } catch let error as GuardrailError {
            if case .inputTripwireTriggered(let name, let message, _) = error {
                XCTAssertEqual(name, "blocker")
                XCTAssertEqual(message, "Always fails")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
}
```

---

## Summary

This implementation plan provides:

1. **Complete code examples** for each phase
2. **OpenAI SDK references** showing the patterns to follow
3. **Integration points** with existing SwiftAgents code
4. **Testing templates** for verification
5. **File organization** following existing patterns

The coding agent should implement these in order, testing each phase before moving to the next.
