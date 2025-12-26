// RunHooks.swift
// SwiftAgents Framework
//
// Lifecycle hooks for observing agent execution events.

import Foundation

// MARK: - RunHooks

/// Protocol for receiving callbacks during agent execution.
///
/// `RunHooks` provides a comprehensive set of lifecycle callbacks that enable
/// monitoring, logging, and custom logic at key points during agent execution.
/// All methods have default no-op implementations, so implementers only need to
/// override the callbacks they care about.
///
/// Use cases:
/// - Logging and observability
/// - Performance monitoring
/// - Debugging and diagnostics
/// - Custom telemetry collection
/// - Usage tracking
///
/// Example:
/// ```swift
/// struct MyHooks: RunHooks {
///     func onAgentStart(context: AgentContext?, agent: any Agent, input: String) async {
///         print("Agent started with: \(input)")
///     }
///
///     func onToolStart(context: AgentContext?, agent: any Agent, tool: any Tool, arguments: [String: SendableValue])
/// async {
///         print("Calling tool: \(tool.name)")
///     }
/// }
///
/// let agent = ReActAgent(
///     tools: [...],
///     instructions: "...",
///     runHooks: [MyHooks(), LoggingRunHooks()]
/// )
/// ```
public protocol RunHooks: Sendable {
    /// Called when an agent begins execution.
    ///
    /// - Parameters:
    ///   - context: Agent context for orchestration scenarios. `nil` when the agent is run standalone
    ///     (directly via `agent.run()` rather than through an orchestrator like `SupervisorAgent`).
    ///   - agent: The agent that is starting.
    ///   - input: The input string passed to the agent.
    func onAgentStart(context: AgentContext?, agent: any Agent, input: String) async

    /// Called when an agent completes execution successfully.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent that completed.
    ///   - result: The result produced by the agent.
    func onAgentEnd(context: AgentContext?, agent: any Agent, result: AgentResult) async

    /// Called when an agent encounters an error during execution.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent that encountered the error.
    ///   - error: The error that occurred.
    func onError(context: AgentContext?, agent: any Agent, error: Error) async

    /// Called when an agent hands off execution to another agent.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - fromAgent: The agent initiating the handoff.
    ///   - toAgent: The agent receiving control.
    func onHandoff(context: AgentContext?, fromAgent: any Agent, toAgent: any Agent) async

    /// Called when a tool execution begins.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent calling the tool.
    ///   - tool: The tool being executed.
    ///   - arguments: The arguments passed to the tool.
    func onToolStart(context: AgentContext?, agent: any Agent, tool: any Tool, arguments: [String: SendableValue]) async

    /// Called when a tool execution completes successfully.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent that called the tool.
    ///   - tool: The tool that was executed.
    ///   - result: The result returned by the tool.
    func onToolEnd(context: AgentContext?, agent: any Agent, tool: any Tool, result: SendableValue) async

    /// Called when an LLM inference begins.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent making the LLM call.
    ///   - systemPrompt: The system prompt, if any.
    ///   - inputMessages: The input messages sent to the LLM.
    func onLLMStart(context: AgentContext?, agent: any Agent, systemPrompt: String?, inputMessages: [MemoryMessage]) async

    /// Called when an LLM inference completes.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent that made the LLM call.
    ///   - response: The text response from the LLM.
    ///   - usage: Token usage statistics, if available.
    func onLLMEnd(context: AgentContext?, agent: any Agent, response: String, usage: InferenceResponse.TokenUsage?) async

    /// Called when a guardrail is triggered during execution.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - guardrailName: The name of the guardrail that was triggered.
    ///   - guardrailType: The type of guardrail (input, output, toolInput, toolOutput).
    ///   - result: The result of the guardrail check.
    func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async
}

// MARK: - RunHooks Default Implementations

public extension RunHooks {
    /// Default no-op implementation for agent start.
    func onAgentStart(context _: AgentContext?, agent _: any Agent, input _: String) async {}

    /// Default no-op implementation for agent end.
    func onAgentEnd(context _: AgentContext?, agent _: any Agent, result _: AgentResult) async {}

    /// Default no-op implementation for errors.
    func onError(context _: AgentContext?, agent _: any Agent, error _: Error) async {}

    /// Default no-op implementation for handoffs.
    func onHandoff(context _: AgentContext?, fromAgent _: any Agent, toAgent _: any Agent) async {}

    /// Default no-op implementation for tool start.
    func onToolStart(context _: AgentContext?, agent _: any Agent, tool _: any Tool, arguments _: [String: SendableValue]) async {}

    /// Default no-op implementation for tool end.
    func onToolEnd(context _: AgentContext?, agent _: any Agent, tool _: any Tool, result _: SendableValue) async {}

    /// Default no-op implementation for LLM start.
    func onLLMStart(context _: AgentContext?, agent _: any Agent, systemPrompt _: String?, inputMessages _: [MemoryMessage]) async {}

    /// Default no-op implementation for LLM end.
    func onLLMEnd(context _: AgentContext?, agent _: any Agent, response _: String, usage _: InferenceResponse.TokenUsage?) async {}

    /// Default no-op implementation for guardrail triggered.
    func onGuardrailTriggered(context _: AgentContext?, guardrailName _: String, guardrailType _: GuardrailType, result _: GuardrailResult) async {}
}

// MARK: - CompositeRunHooks

/// Composite hook implementation that delegates to multiple hooks.
///
/// `CompositeRunHooks` allows combining multiple hook implementations so they
/// all receive callbacks. Hooks are executed **concurrently** using structured
/// concurrency for optimal performance.
///
/// - Important: Hooks are **scheduled** in registration order but execute **concurrently**.
///   Completion order is not guaranteed. For strictly ordered execution, use a single hook
///   that coordinates multiple handlers internally.
/// - Note: Hook implementations must be thread-safe and handle concurrent invocation.
///   Since `RunHooks` methods are not `throws`, implementations cannot propagate errors.
///   Any internal errors should be logged rather than thrown.
///
/// Example:
/// ```swift
/// let composite = CompositeRunHooks(hooks: [
///     LoggingRunHooks(),
///     MetricsRunHooks(),
///     CustomDebugHooks()
/// ])
///
/// let agent = ReActAgent(
///     tools: [...],
///     instructions: "...",
///     runHooks: [composite]
/// )
/// ```
public struct CompositeRunHooks: RunHooks {
    // MARK: Public

    // MARK: - Initialization

    /// Creates a composite hook that delegates to multiple hooks.
    ///
    /// - Parameter hooks: The hooks to delegate to.
    public init(hooks: [any RunHooks]) {
        self.hooks = hooks
    }

    // MARK: - RunHooks Implementation

    public func onAgentStart(context: AgentContext?, agent: any Agent, input: String) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in hooks {
                group.addTask {
                    await hook.onAgentStart(context: context, agent: agent, input: input)
                }
            }
        }
    }

    public func onAgentEnd(context: AgentContext?, agent: any Agent, result: AgentResult) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in hooks {
                group.addTask {
                    await hook.onAgentEnd(context: context, agent: agent, result: result)
                }
            }
        }
    }

    public func onError(context: AgentContext?, agent: any Agent, error: Error) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in hooks {
                group.addTask {
                    await hook.onError(context: context, agent: agent, error: error)
                }
            }
        }
    }

    public func onHandoff(context: AgentContext?, fromAgent: any Agent, toAgent: any Agent) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in hooks {
                group.addTask {
                    await hook.onHandoff(context: context, fromAgent: fromAgent, toAgent: toAgent)
                }
            }
        }
    }

    public func onToolStart(context: AgentContext?, agent: any Agent, tool: any Tool, arguments: [String: SendableValue]) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in hooks {
                group.addTask {
                    await hook.onToolStart(context: context, agent: agent, tool: tool, arguments: arguments)
                }
            }
        }
    }

    public func onToolEnd(context: AgentContext?, agent: any Agent, tool: any Tool, result: SendableValue) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in hooks {
                group.addTask {
                    await hook.onToolEnd(context: context, agent: agent, tool: tool, result: result)
                }
            }
        }
    }

    public func onLLMStart(context: AgentContext?, agent: any Agent, systemPrompt: String?, inputMessages: [MemoryMessage]) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in hooks {
                group.addTask {
                    await hook.onLLMStart(context: context, agent: agent, systemPrompt: systemPrompt, inputMessages: inputMessages)
                }
            }
        }
    }

    public func onLLMEnd(context: AgentContext?, agent: any Agent, response: String, usage: InferenceResponse.TokenUsage?) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in hooks {
                group.addTask {
                    await hook.onLLMEnd(context: context, agent: agent, response: response, usage: usage)
                }
            }
        }
    }

    public func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in hooks {
                group.addTask {
                    await hook.onGuardrailTriggered(context: context, guardrailName: guardrailName, guardrailType: guardrailType, result: result)
                }
            }
        }
    }

    // MARK: Private

    /// The hooks to delegate to.
    private let hooks: [any RunHooks]
}

// MARK: - LoggingRunHooks

/// Hook implementation that logs all agent events using swift-log.
///
/// `LoggingRunHooks` provides comprehensive logging of all agent lifecycle
/// events using the `Log.agents` logger. This is useful for debugging,
/// observability, and understanding agent execution flow.
///
/// Log levels:
/// - `.info`: Agent start/end, tool start/end, LLM start/end, handoff
/// - `.warning`: Guardrail triggered
/// - `.error`: Error events
///
/// Example:
/// ```swift
/// let agent = ReActAgent(
///     tools: [...],
///     instructions: "...",
///     runHooks: [LoggingRunHooks()]
/// )
/// ```
public struct LoggingRunHooks: RunHooks {
    // MARK: Public

    // MARK: - Initialization

    /// Creates a new logging hook.
    public init() {}

    // MARK: - RunHooks Implementation

    public func onAgentStart(context: AgentContext?, agent _: any Agent, input: String) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        let truncatedInput = input.count > 100 ? String(input.prefix(100)) + "..." : input
        Log.agents.info("Agent started\(contextId) - input: \"\(truncatedInput)\"")
    }

    public func onAgentEnd(context: AgentContext?, agent _: any Agent, result: AgentResult) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.info("Agent completed\(contextId) - iterations: \(result.iterationCount), duration: \(result.duration), tools: \(result.toolCalls.count)")
    }

    public func onError(context: AgentContext?, agent _: any Agent, error: Error) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.error("Agent error\(contextId) - \(error.localizedDescription)")
    }

    public func onHandoff(context: AgentContext?, fromAgent: any Agent, toAgent: any Agent) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        let fromName = agentDisplayName(fromAgent)
        let toName = agentDisplayName(toAgent)
        Log.agents.info("Agent handoff\(contextId) - from: \(fromName) to: \(toName)")
    }

    public func onToolStart(context: AgentContext?, agent _: any Agent, tool: any Tool, arguments: [String: SendableValue]) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.info("Tool started\(contextId) - name: \(tool.name), args: \(arguments.count) parameter(s)")
    }

    public func onToolEnd(context: AgentContext?, agent _: any Agent, tool: any Tool, result _: SendableValue) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.info("Tool completed\(contextId) - name: \(tool.name)")
    }

    public func onLLMStart(context: AgentContext?, agent _: any Agent, systemPrompt _: String?, inputMessages: [MemoryMessage]) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.info("LLM call started\(contextId) - messages: \(inputMessages.count)")
    }

    public func onLLMEnd(context: AgentContext?, agent _: any Agent, response _: String, usage: InferenceResponse.TokenUsage?) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        let usageInfo = if let usage {
            ", tokens: \(usage.inputTokens) in / \(usage.outputTokens) out"
        } else {
            ""
        }
        Log.agents.info("LLM call completed\(contextId)\(usageInfo)")
    }

    public func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        let message = result.message ?? "No message provided"
        Log.agents.warning("Guardrail triggered\(contextId) - name: \(guardrailName), type: \(guardrailType.rawValue), message: \(message)")
    }

    // MARK: Private

    // MARK: - Private Helpers

    /// Returns a display name for an agent, falling back to type name if configuration name is empty.
    private func agentDisplayName(_ agent: any Agent) -> String {
        let name = agent.configuration.name
        return name.isEmpty ? String(describing: type(of: agent)) : name
    }
}
