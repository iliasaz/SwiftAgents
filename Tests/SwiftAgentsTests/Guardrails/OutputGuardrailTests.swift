// OutputGuardrailTests.swift
// SwiftAgentsTests
//
// TDD tests for OutputGuardrail protocol and implementations.
// These tests define the contract for OutputGuardrail before implementation.

import Foundation
@testable import SwiftAgents
import Testing

// MARK: - MockAgent

/// A minimal mock agent for testing guardrails.
struct MockAgent: Agent {
    nonisolated let tools: [any Tool]
    nonisolated let instructions: String
    nonisolated let configuration: AgentConfiguration
    nonisolated let memory: (any Memory)?
    nonisolated let inferenceProvider: (any InferenceProvider)?
    nonisolated let tracer: (any Tracer)?
    
    let mockResult: AgentResult
    
    init(
        tools: [any Tool] = [],
        instructions: String = "Mock agent instructions",
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        inferenceProvider: (any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        mockResult: AgentResult = AgentResult(
            output: "Mock agent output",
            toolCalls: [],
            toolResults: [],
            iterationCount: 1
        )
    ) {
        self.tools = tools
        self.instructions = instructions
        self.configuration = configuration
        self.memory = memory
        self.inferenceProvider = inferenceProvider
        self.tracer = tracer
        self.mockResult = mockResult
    }
    
    func run(_ input: String) async throws -> AgentResult {
        mockResult
    }
    
    nonisolated func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(input: input))
            continuation.finish()
        }
    }
    
    func cancel() async {}
}

// MARK: - OutputGuardrailTests

@Suite("OutputGuardrail Protocol Tests")
struct OutputGuardrailTests {
    
    // MARK: - Protocol Conformance Tests
    
    @Test("OutputGuardrail protocol requires name property")
    func testProtocolRequiresName() async throws {
        // Given
        let guardrail = ClosureOutputGuardrail(name: "test_guardrail") { _, _, _ in
            .passed()
        }
        
        // Then
        #expect(guardrail.name == "test_guardrail")
    }
    
    @Test("OutputGuardrail protocol requires validate method")
    func testProtocolRequiresValidateMethod() async throws {
        // Given
        let agent = MockAgent()
        let guardrail = ClosureOutputGuardrail(name: "test") { output, _, _ in
            #expect(output == "test output")
            return .passed()
        }
        
        // When
        let result = try await guardrail.validate("test output", agent: agent, context: nil)
        
        // Then
        #expect(result.tripwireTriggered == false)
    }
    
    // MARK: - ClosureOutputGuardrail Basic Tests
    
    @Test("ClosureOutputGuardrail stores name correctly")
    func testClosureGuardrailName() {
        // Given
        let name = "content_filter"
        let guardrail = ClosureOutputGuardrail(name: name) { _, _, _ in .passed() }
        
        // Then
        #expect(guardrail.name == name)
    }
    
    @Test("ClosureOutputGuardrail executes handler on validate")
    func testClosureGuardrailExecutesHandler() async throws {
        // Given
        actor CallCapture {
            var called = false
            func set() { called = true }
            func get() -> Bool { called }
        }
        let capture = CallCapture()
        let guardrail = ClosureOutputGuardrail(name: "test") { _, _, _ in
            await capture.set()
            return .passed()
        }
        let agent = MockAgent()

        // When
        _ = try await guardrail.validate("output", agent: agent, context: nil)

        // Then
        let wasCalled = await capture.get()
        #expect(wasCalled == true)
    }
    
    // MARK: - Passed Result Tests
    
    @Test("ClosureOutputGuardrail returns passed result")
    func testClosureGuardrailPassedResult() async throws {
        // Given
        let guardrail = ClosureOutputGuardrail(name: "allow_all") { _, _, _ in
            .passed(message: "Content is safe")
        }
        let agent = MockAgent()
        
        // When
        let result = try await guardrail.validate("Safe output", agent: agent, context: nil)
        
        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == "Content is safe")
    }
    
    @Test("ClosureOutputGuardrail passes output to handler")
    func testClosureGuardrailReceivesOutput() async throws {
        // Given
        let expectedOutput = "This is the output to validate"
        let guardrail = ClosureOutputGuardrail(name: "validator") { output, _, _ in
            #expect(output == expectedOutput)
            return .passed()
        }
        let agent = MockAgent()
        
        // When
        _ = try await guardrail.validate(expectedOutput, agent: agent, context: nil)
    }
    
    // MARK: - Tripwire Result Tests
    
    @Test("ClosureOutputGuardrail returns tripwire result")
    func testClosureGuardrailTripwireResult() async throws {
        // Given
        let guardrail = ClosureOutputGuardrail(name: "block_profanity") { output, _, _ in
            if output.contains("badword") {
                return .tripwire(
                    message: "Profanity detected",
                    outputInfo: .dictionary(["word": .string("badword")])
                )
            }
            return .passed()
        }
        let agent = MockAgent()
        
        // When
        let result = try await guardrail.validate("This contains badword", agent: agent, context: nil)
        
        // Then
        #expect(result.tripwireTriggered == true)
        #expect(result.message == "Profanity detected")
        #expect(result.outputInfo != nil)
    }
    
    @Test("ClosureOutputGuardrail tripwire result includes outputInfo")
    func testClosureGuardrailTripwireOutputInfo() async throws {
        // Given
        let violationInfo: SendableValue = .dictionary([
            "type": .string("PII"),
            "patterns": .array([.string("SSN"), .string("CREDIT_CARD")])
        ])
        
        let guardrail = ClosureOutputGuardrail(name: "pii_detector") { _, _, _ in
            .tripwire(message: "PII detected", outputInfo: violationInfo)
        }
        let agent = MockAgent()
        
        // When
        let result = try await guardrail.validate("SSN: 123-45-6789", agent: agent, context: nil)
        
        // Then
        #expect(result.tripwireTriggered == true)
        #expect(result.outputInfo == violationInfo)
    }
    
    // MARK: - Agent Parameter Tests
    
    @Test("ClosureOutputGuardrail receives agent parameter")
    func testClosureGuardrailWithAgent() async throws {
        // Given
        let expectedInstructions = "Test agent instructions"
        let agent = MockAgent(instructions: expectedInstructions)
        
        let guardrail = ClosureOutputGuardrail(name: "agent_checker") { _, receivedAgent, _ in
            #expect(receivedAgent.instructions == expectedInstructions)
            return .passed()
        }
        
        // When
        _ = try await guardrail.validate("output", agent: agent, context: nil)
    }
    
    @Test("ClosureOutputGuardrail can access agent configuration")
    func testClosureGuardrailAccessesAgentConfig() async throws {
        // Given
        let config = AgentConfiguration.default.maxIterations(10)
        let agent = MockAgent(configuration: config)
        
        let guardrail = ClosureOutputGuardrail(name: "config_checker") { _, receivedAgent, _ in
            #expect(receivedAgent.configuration.maxIterations == 10)
            return .passed()
        }
        
        // When
        _ = try await guardrail.validate("output", agent: agent, context: nil)
    }
    
    @Test("ClosureOutputGuardrail can access agent tools")
    func testClosureGuardrailAccessesAgentTools() async throws {
        // Given
        let tool = MockTool(name: "calculator")
        let agent = MockAgent(tools: [tool])
        
        let guardrail = ClosureOutputGuardrail(name: "tool_checker") { _, receivedAgent, _ in
            #expect(receivedAgent.tools.count == 1)
            #expect(receivedAgent.tools[0].name == "calculator")
            return .passed()
        }
        
        // When
        _ = try await guardrail.validate("output", agent: agent, context: nil)
    }
    
    // MARK: - Context Parameter Tests
    
    @Test("ClosureOutputGuardrail receives nil context when not provided")
    func testClosureGuardrailWithNilContext() async throws {
        // Given
        let guardrail = ClosureOutputGuardrail(name: "context_checker") { _, _, context in
            #expect(context == nil)
            return .passed()
        }
        let agent = MockAgent()
        
        // When
        _ = try await guardrail.validate("output", agent: agent, context: nil)
    }
    
    @Test("ClosureOutputGuardrail receives context when provided")
    func testClosureGuardrailWithContext() async throws {
        // Given
        let context = AgentContext(input: "Original query")
        await context.set("custom_key", value: .string("custom_value"))
        
        let guardrail = ClosureOutputGuardrail(name: "context_reader") { _, _, receivedContext in
            #expect(receivedContext != nil)
            return .passed()
        }
        let agent = MockAgent()
        
        // When
        _ = try await guardrail.validate("output", agent: agent, context: context)
    }
    
    @Test("ClosureOutputGuardrail can read context values")
    func testClosureGuardrailReadsContextValues() async throws {
        // Given
        let context = AgentContext(input: "Test input")
        await context.set("validation_mode", value: .string("strict"))
        
        let guardrail = ClosureOutputGuardrail(name: "context_validator") { _, _, ctx in
            Task {
                if let mode = await ctx?.get("validation_mode")?.stringValue {
                    #expect(mode == "strict")
                }
            }
            return .passed()
        }
        let agent = MockAgent()
        
        // When
        _ = try await guardrail.validate("output", agent: agent, context: context)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("ClosureOutputGuardrail propagates thrown errors")
    func testClosureGuardrailThrowsError() async {
        // Given
        struct TestError: Error, Equatable {}
        let guardrail = ClosureOutputGuardrail(name: "error_thrower") { _, _, _ in
            throw TestError()
        }
        let agent = MockAgent()
        
        // When/Then
        do {
            _ = try await guardrail.validate("output", agent: agent, context: nil as AgentContext?)
            Issue.record("Expected TestError to be thrown")
        } catch is TestError {
            // Success - error was propagated
        } catch {
            Issue.record("Expected TestError but got: \(error)")
        }
    }
    
    @Test("ClosureOutputGuardrail handles async errors")
    func testClosureGuardrailAsyncError() async {
        // Given
        let guardrail = ClosureOutputGuardrail(name: "async_error") { _, _, _ in
            try await Task.sleep(for: .milliseconds(1))
            throw AgentError.internalError(reason: "Async failure")
        }
        let agent = MockAgent()

        // When/Then
        do {
            _ = try await guardrail.validate("output", agent: agent, context: nil as AgentContext?)
            Issue.record("Expected AgentError to be thrown")
        } catch let error as AgentError {
            // Verify the error
            switch error {
            case .internalError:
                break // Success
            default:
                Issue.record("Expected internalError but got: \(error)")
            }
        } catch {
            Issue.record("Expected AgentError but got: \(error)")
        }
    }
    
    // MARK: - Sendable Conformance Tests
    
    @Test("OutputGuardrail is Sendable across async boundaries")
    func testOutputGuardrailSendable() async throws {
        // Given
        let guardrail = ClosureOutputGuardrail(name: "sendable_test") { _, _, _ in
            .passed(message: "Sent across boundary")
        }
        
        // When - pass guardrail across async boundary
        let receivedGuardrail = await withCheckedContinuation { continuation in
            Task {
                continuation.resume(returning: guardrail)
            }
        }
        
        let agent = MockAgent()
        let result = try await receivedGuardrail.validate("output", agent: agent, context: nil as AgentContext?)
        
        // Then
        #expect(result.message == "Sent across boundary")
    }
    
    @Test("OutputGuardrail can be used in Task context")
    func testOutputGuardrailInTask() async throws {
        // Given
        let guardrail = ClosureOutputGuardrail(name: "task_test") { _, _, _ in
            .passed()
        }
        let agent = MockAgent()
        
        // When - use in Task
        let taskResult = try await Task {
            try await guardrail.validate("output", agent: agent, context: nil as AgentContext?)
        }.value

        // Then
        #expect(taskResult.tripwireTriggered == false)
    }
    
    @Test("OutputGuardrail can be stored in actor")
    func testOutputGuardrailWithActor() async throws {
        // Given
        actor GuardrailStore {
            private var storedGuardrail: (any OutputGuardrail)?
            
            func store(_ guardrail: any OutputGuardrail) {
                storedGuardrail = guardrail
            }
            
            func retrieve() -> (any OutputGuardrail)? {
                storedGuardrail
            }
        }
        
        let store = GuardrailStore()
        let guardrail = ClosureOutputGuardrail(name: "stored") { _, _, _ in .passed() }
        
        // When
        await store.store(guardrail)
        let retrieved = await store.retrieve()
        
        // Then
        #expect(retrieved != nil)
        #expect(retrieved?.name == "stored")
    }
    
    // MARK: - Multiple Guardrails Tests
    
    @Test("Multiple OutputGuardrails can be composed")
    func testMultipleOutputGuardrails() async throws {
        // Given
        let guardrail1 = ClosureOutputGuardrail(name: "length_check") { output, _, _ in
            if output.count < 10 {
                return .tripwire(message: "Output too short")
            }
            return .passed()
        }
        
        let guardrail2 = ClosureOutputGuardrail(name: "content_check") { output, _, _ in
            if output.contains("forbidden") {
                return .tripwire(message: "Forbidden content")
            }
            return .passed()
        }
        
        let guardrails: [any OutputGuardrail] = [guardrail1, guardrail2]
        let agent = MockAgent()
        
        // When - validate with passing output
        let passingOutput = "This is a safe and long enough output"
        var allPassed = true
        
        for guardrail in guardrails {
            let result = try await guardrail.validate(passingOutput, agent: agent, context: nil as AgentContext?)
            if result.tripwireTriggered {
                allPassed = false
                break
            }
        }
        
        // Then
        #expect(allPassed == true)
        
        // When - validate with failing output (too short)
        let shortOutput = "Short"
        var anyTripped = false
        
        for guardrail in guardrails {
            let result = try await guardrail.validate(shortOutput, agent: agent, context: nil as AgentContext?)
            if result.tripwireTriggered {
                anyTripped = true
                break
            }
        }
        
        // Then
        #expect(anyTripped == true)
    }
    
    @Test("Multiple OutputGuardrails can run sequentially")
    func testMultipleGuardrailsSequential() async throws {
        // Given
        actor OrderCapture {
            var order: [String] = []
            func append(_ name: String) { order.append(name) }
            func get() -> [String] { order }
        }
        let orderCapture = OrderCapture()

        let guardrail1 = ClosureOutputGuardrail(name: "first") { _, _, _ in
            await orderCapture.append("first")
            return .passed()
        }

        let guardrail2 = ClosureOutputGuardrail(name: "second") { _, _, _ in
            await orderCapture.append("second")
            return .passed()
        }

        let guardrail3 = ClosureOutputGuardrail(name: "third") { _, _, _ in
            await orderCapture.append("third")
            return .passed()
        }

        let guardrails: [any OutputGuardrail] = [guardrail1, guardrail2, guardrail3]
        let agent = MockAgent()

        // When - run all guardrails sequentially
        for guardrail in guardrails {
            _ = try await guardrail.validate("output", agent: agent, context: nil as AgentContext?)
        }

        // Then
        let executionOrder = await orderCapture.get()
        #expect(executionOrder == ["first", "second", "third"])
    }
    
    @Test("Multiple OutputGuardrails short-circuit on tripwire")
    func testMultipleGuardrailsShortCircuit() async throws {
        // Given
        actor LogCapture {
            var log: [String] = []
            func append(_ name: String) { log.append(name) }
            func get() -> [String] { log }
        }
        let logCapture = LogCapture()

        let guardrail1 = ClosureOutputGuardrail(name: "first") { _, _, _ in
            await logCapture.append("first")
            return .passed()
        }

        let guardrail2 = ClosureOutputGuardrail(name: "second") { _, _, _ in
            await logCapture.append("second")
            return .tripwire(message: "Second guardrail blocks")
        }

        let guardrail3 = ClosureOutputGuardrail(name: "third") { _, _, _ in
            await logCapture.append("third")
            return .passed()
        }

        let guardrails: [any OutputGuardrail] = [guardrail1, guardrail2, guardrail3]
        let agent = MockAgent()

        // When - run until tripwire
        for guardrail in guardrails {
            let result = try await guardrail.validate("output", agent: agent, context: nil as AgentContext?)
            if result.tripwireTriggered {
                break // Short-circuit
            }
        }

        // Then - third guardrail should not have executed
        let executionLog = await logCapture.get()
        #expect(executionLog == ["first", "second"])
        #expect(!executionLog.contains("third"))
    }
    
    // MARK: - Edge Cases
    
    @Test("OutputGuardrail validates empty output")
    func testOutputGuardrailEmptyOutput() async throws {
        // Given
        let guardrail = ClosureOutputGuardrail(name: "empty_checker") { output, _, _ in
            if output.isEmpty {
                return .tripwire(message: "Output is empty")
            }
            return .passed()
        }
        let agent = MockAgent()
        
        // When
        let result = try await guardrail.validate("", agent: agent, context: nil as AgentContext?)
        
        // Then
        #expect(result.tripwireTriggered == true)
        #expect(result.message == "Output is empty")
    }
    
    @Test("OutputGuardrail validates very long output")
    func testOutputGuardrailLongOutput() async throws {
        // Given
        let longOutput = String(repeating: "a", count: 10_000)
        let guardrail = ClosureOutputGuardrail(name: "length_validator") { output, _, _ in
            if output.count > 5000 {
                return .tripwire(
                    message: "Output exceeds maximum length",
                    metadata: ["length": .int(output.count)]
                )
            }
            return .passed()
        }
        let agent = MockAgent()
        
        // When
        let result = try await guardrail.validate(longOutput, agent: agent, context: nil as AgentContext?)
        
        // Then
        #expect(result.tripwireTriggered == true)
        #expect(result.metadata["length"]?.intValue == 10_000)
    }
    
    @Test("OutputGuardrail handles multiline output")
    func testOutputGuardrailMultilineOutput() async throws {
        // Given
        let multilineOutput = """
        Line 1
        Line 2
        Line 3
        """
        
        let guardrail = ClosureOutputGuardrail(name: "line_counter") { output, _, _ in
            let lineCount = output.components(separatedBy: "\n").count
            return .passed(
                message: "Validated \(lineCount) lines",
                metadata: ["lineCount": .int(lineCount)]
            )
        }
        let agent = MockAgent()
        
        // When
        let result = try await guardrail.validate(multilineOutput, agent: agent, context: nil as AgentContext?)
        
        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.metadata["lineCount"]?.intValue == 3)
    }
    
    @Test("OutputGuardrail handles special characters")
    func testOutputGuardrailSpecialCharacters() async throws {
        // Given
        let specialOutput = "Special chars: \n\t\r\"'\\@#$%^&*()"
        let guardrail = ClosureOutputGuardrail(name: "special_char_validator") { output, _, _ in
            if output.contains("\\") {
                return .tripwire(message: "Backslash detected")
            }
            return .passed()
        }
        let agent = MockAgent()
        
        // When
        let result = try await guardrail.validate(specialOutput, agent: agent, context: nil as AgentContext?)
        
        // Then
        #expect(result.tripwireTriggered == true)
    }
    
    @Test("OutputGuardrail handles unicode characters")
    func testOutputGuardrailUnicode() async throws {
        // Given
        let unicodeOutput = "Hello 世界 🌍 émoji"
        let guardrail = ClosureOutputGuardrail(name: "unicode_validator") { output, _, _ in
            .passed(
                message: "Unicode validated",
                metadata: ["characterCount": .int(output.count)]
            )
        }
        let agent = MockAgent()
        
        // When
        let result = try await guardrail.validate(unicodeOutput, agent: agent, context: nil as AgentContext?)
        
        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.metadata["characterCount"] != nil)
    }
    
    // MARK: - Concurrent Execution Tests
    
    @Test("OutputGuardrail can be called concurrently")
    func testOutputGuardrailConcurrentCalls() async throws {
        // Given
        actor CallCounter {
            var count = 0
            func increment() { count += 1 }
            func getCount() -> Int { count }
        }
        
        let counter = CallCounter()
        let guardrail = ClosureOutputGuardrail(name: "concurrent") { _, _, _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(10))
            return .passed()
        }
        let agent = MockAgent()
        
        // When - execute 5 concurrent validations
        await withTaskGroup(of: Void.self) { group in
            for i in 1...5 {
                group.addTask {
                    _ = try? await guardrail.validate("output \(i)", agent: agent, context: nil as AgentContext?)
                }
            }
        }
        
        // Then
        let finalCount = await counter.getCount()
        #expect(finalCount == 5)
    }
}
