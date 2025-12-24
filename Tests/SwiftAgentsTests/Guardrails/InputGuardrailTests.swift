// InputGuardrailTests.swift
// SwiftAgentsTests
//
// TDD tests for InputGuardrail protocol and implementations
// These tests define the contract before implementation

import Foundation
@testable import SwiftAgents
import Testing

// MARK: - InputGuardrailTests

@Suite("InputGuardrail Tests")
struct InputGuardrailTests {
    
    // MARK: - Protocol Conformance Tests
    
    @Test("InputGuardrail protocol requires name property")
    func testInputGuardrailProtocolNameRequirement() async throws {
        // Given
        struct TestGuardrail: InputGuardrail {
            let name: String
            func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
                .passed()
            }
        }
        
        // When
        let guardrail = TestGuardrail(name: "TestGuardrail")
        
        // Then
        #expect(guardrail.name == "TestGuardrail")
    }
    
    @Test("InputGuardrail protocol requires validate method")
    func testInputGuardrailProtocolValidateRequirement() async throws {
        // Given
        struct TestGuardrail: InputGuardrail {
            let name: String
            func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
                .passed(message: "Validation passed")
            }
        }
        
        // When
        let guardrail = TestGuardrail(name: "Test")
        let result = try await guardrail.validate("test input", context: nil)
        
        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == "Validation passed")
    }
    
    @Test("InputGuardrail is Sendable across async boundaries")
    func testInputGuardrailSendableConformance() async throws {
        // Given
        struct SendableTestGuardrail: InputGuardrail {
            let name: String
            func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
                .passed()
            }
        }
        
        let guardrail = SendableTestGuardrail(name: "Sendable")
        
        // When - pass across async boundary
        let result = try await Task {
            try await guardrail.validate("test", context: nil)
        }.value

        // Then
        #expect(result.tripwireTriggered == false)
    }
    
    // MARK: - ClosureInputGuardrail Tests
    
    @Test("ClosureInputGuardrail initializes with name and handler")
    func testClosureInputGuardrailInitialization() {
        // When
        let guardrail = ClosureInputGuardrail(name: "TestGuardrail") { input, context in
            .passed()
        }
        
        // Then
        #expect(guardrail.name == "TestGuardrail")
    }
    
    @Test("ClosureInputGuardrail validates with passed result")
    func testClosureInputGuardrailPassedResult() async throws {
        // Given
        let guardrail = ClosureInputGuardrail(name: "PassGuardrail") { input, context in
            .passed(message: "Input is valid")
        }
        
        // When
        let result = try await guardrail.validate("test input", context: nil)
        
        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == "Input is valid")
    }
    
    @Test("ClosureInputGuardrail validates with tripwire result")
    func testClosureInputGuardrailTripwireResult() async throws {
        // Given
        let guardrail = ClosureInputGuardrail(name: "TripwireGuardrail") { input, context in
            .tripwire(message: "Sensitive data detected")
        }
        
        // When
        let result = try await guardrail.validate("SSN: 123-45-6789", context: nil)
        
        // Then
        #expect(result.tripwireTriggered == true)
        #expect(result.message == "Sensitive data detected")
    }
    
    @Test("ClosureInputGuardrail handler receives input")
    func testClosureInputGuardrailReceivesInput() async throws {
        // Given
        actor InputCapture {
            var value: String?
            func set(_ newValue: String) { value = newValue }
            func get() -> String? { value }
        }

        let capture = InputCapture()
        let guardrail = ClosureInputGuardrail(name: "CaptureGuardrail") { input, context in
            await capture.set(input)
            return .passed()
        }

        // When
        _ = try await guardrail.validate("test input", context: nil)

        // Then
        let capturedInput = await capture.get()
        #expect(capturedInput == "test input")
    }
    
    @Test("ClosureInputGuardrail handler receives context")
    func testClosureInputGuardrailReceivesContext() async throws {
        // Given
        let testContext = AgentContext(input: "test")
        await testContext.set("customKey", value: .string("original"))

        actor ContextCapture {
            var value: AgentContext?
            func set(_ newValue: AgentContext?) { value = newValue }
            func get() -> AgentContext? { value }
        }

        let capture = ContextCapture()
        let guardrail = ClosureInputGuardrail(name: "ContextGuardrail") { input, context in
            await capture.set(context)
            return .passed()
        }

        // When
        _ = try await guardrail.validate("test", context: testContext)

        // Then
        let capturedContext = await capture.get()
        #expect(capturedContext != nil)
        let customValue = await capturedContext?.get("customKey")
        #expect(customValue?.stringValue == "original")
    }
    
    @Test("ClosureInputGuardrail works with nil context")
    func testClosureInputGuardrailWithNilContext() async throws {
        // Given
        actor ContextCapture {
            var value: AgentContext?
            var wasSet = false
            func set(_ newValue: AgentContext?) {
                value = newValue
                wasSet = true
            }
            func get() -> AgentContext? { value }
            func didSet() -> Bool { wasSet }
        }

        let capture = ContextCapture()
        let guardrail = ClosureInputGuardrail(name: "NilContextGuardrail") { input, context in
            await capture.set(context)
            return .passed()
        }

        // When
        let result = try await guardrail.validate("test", context: nil)

        // Then
        let receivedContext = await capture.get()
        #expect(receivedContext == nil)
        #expect(result.tripwireTriggered == false)
    }
    
    @Test("ClosureInputGuardrail propagates errors from handler")
    func testClosureInputGuardrailThrowsError() async {
        // Given
        struct TestError: Error {}
        let guardrail = ClosureInputGuardrail(name: "ErrorGuardrail") { input, context in
            throw TestError()
        }
        
        // When/Then
        await #expect(throws: TestError.self) {
            _ = try await guardrail.validate("test", context: nil)
        }
    }
    
    @Test("ClosureInputGuardrail name property is accessible")
    func testClosureInputGuardrailNameProperty() {
        // Given
        let guardrail = ClosureInputGuardrail(name: "NamedGuardrail") { input, context in
            .passed()
        }
        
        // When
        let name = guardrail.name
        
        // Then
        #expect(name == "NamedGuardrail")
    }
    
    @Test("ClosureInputGuardrail supports concurrent validations")
    func testClosureInputGuardrailConcurrentExecution() async throws {
        // Given
        actor ValidationCounter {
            private var count = 0
            func increment() { count += 1 }
            func getCount() -> Int { count }
        }
        
        let counter = ValidationCounter()
        let guardrail = ClosureInputGuardrail(name: "ConcurrentGuardrail") { input, context in
            await counter.increment()
            return .passed()
        }
        
        // When - execute 10 concurrent validations
        try await withThrowingTaskGroup(of: GuardrailResult.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try await guardrail.validate("input \(i)", context: nil)
                }
            }
            
            for try await _ in group {}
        }
        
        // Then
        let finalCount = await counter.getCount()
        #expect(finalCount == 10)
    }
    
    @Test("ClosureInputGuardrail returns outputInfo from handler")
    func testClosureInputGuardrailWithOutputInfo() async throws {
        // Given
        let outputInfo: SendableValue = .dictionary([
            "tokensChecked": .int(42),
            "category": .string("safe")
        ])
        
        let guardrail = ClosureInputGuardrail(name: "InfoGuardrail") { input, context in
            .passed(outputInfo: outputInfo)
        }
        
        // When
        let result = try await guardrail.validate("test", context: nil)
        
        // Then
        #expect(result.outputInfo == outputInfo)
    }
    
    @Test("ClosureInputGuardrail returns metadata from handler")
    func testClosureInputGuardrailWithMetadata() async throws {
        // Given
        let metadata: [String: SendableValue] = [
            "duration": .double(0.123),
            "version": .string("1.0")
        ]
        
        let guardrail = ClosureInputGuardrail(name: "MetadataGuardrail") { input, context in
            .passed(metadata: metadata)
        }
        
        // When
        let result = try await guardrail.validate("test", context: nil)
        
        // Then
        #expect(result.metadata == metadata)
    }
    
    // MARK: - InputGuardrailBuilder Tests
    
    @Test("InputGuardrailBuilder builds with name and handler")
    func testInputGuardrailBuilderBasic() throws {
        // When
        let guardrail = InputGuardrailBuilder()
            .name("TestGuardrail")
            .validate { input, context in
                .passed()
            }
            .build()
        
        // Then
        #expect(guardrail.name == "TestGuardrail")
    }
    
    @Test("InputGuardrailBuilder supports fluent chaining")
    func testInputGuardrailBuilderFluentChaining() throws {
        // When
        let builder1 = InputGuardrailBuilder()
        let builder2 = builder1.name("Test")
        let builder3 = builder2.validate { input, context in .passed() }
        let guardrail = builder3.build()
        
        // Then
        #expect(guardrail.name == "Test")
    }
    
    @Test("InputGuardrailBuilder creates ClosureInputGuardrail")
    func testInputGuardrailBuilderCreatesCorrectType() throws {
        // When
        let guardrail = InputGuardrailBuilder()
            .name("TypeTest")
            .validate { input, context in .passed() }
            .build()
        
        // Then
        #expect(guardrail is ClosureInputGuardrail)
        #expect(guardrail is any InputGuardrail)
    }
    
    @Test("InputGuardrailBuilder preserves name")
    func testInputGuardrailBuilderPreservesName() throws {
        // Given
        let expectedName = "PreservedName"
        
        // When
        let guardrail = InputGuardrailBuilder()
            .name(expectedName)
            .validate { input, context in .passed() }
            .build()
        
        // Then
        #expect(guardrail.name == expectedName)
    }
    
    @Test("InputGuardrailBuilder preserves handler")
    func testInputGuardrailBuilderPreservesHandler() async throws {
        // Given
        let expectedMessage = "Handler preserved"
        
        // When
        let guardrail = InputGuardrailBuilder()
            .name("Test")
            .validate { input, context in
                .passed(message: expectedMessage)
            }
            .build()
        
        let result = try await guardrail.validate("test", context: nil)
        
        // Then
        #expect(result.message == expectedMessage)
    }
    
    @Test("InputGuardrailBuilder allows multiple names with last winning")
    func testInputGuardrailBuilderMultipleNames() throws {
        // When
        let guardrail = InputGuardrailBuilder()
            .name("FirstName")
            .name("SecondName")
            .validate { input, context in .passed() }
            .build()
        
        // Then
        #expect(guardrail.name == "SecondName")
    }
    
    @Test("InputGuardrailBuilder allows multiple handlers with last winning")
    func testInputGuardrailBuilderMultipleHandlers() async throws {
        // When
        let guardrail = InputGuardrailBuilder()
            .name("Test")
            .validate { input, context in .passed(message: "First") }
            .validate { input, context in .passed(message: "Second") }
            .build()
        
        let result = try await guardrail.validate("test", context: nil)
        
        // Then
        #expect(result.message == "Second")
    }
    
    // MARK: - Integration Tests
    
    @Test("Multiple guardrails execute sequentially")
    func testMultipleGuardrailsSequential() async throws {
        // Given
        actor ExecutionOrder {
            private var order: [String] = []
            func append(_ name: String) { order.append(name) }
            func getOrder() -> [String] { order }
        }
        
        let executionOrder = ExecutionOrder()
        
        let guardrail1 = ClosureInputGuardrail(name: "First") { input, context in
            await executionOrder.append("First")
            return .passed()
        }
        
        let guardrail2 = ClosureInputGuardrail(name: "Second") { input, context in
            await executionOrder.append("Second")
            return .passed()
        }
        
        let guardrail3 = ClosureInputGuardrail(name: "Third") { input, context in
            await executionOrder.append("Third")
            return .passed()
        }
        
        // When
        _ = try await guardrail1.validate("test", context: nil)
        _ = try await guardrail2.validate("test", context: nil)
        _ = try await guardrail3.validate("test", context: nil)
        
        // Then
        let order = await executionOrder.getOrder()
        #expect(order == ["First", "Second", "Third"])
    }
    
    @Test("Guardrail works with actor-isolated AgentContext")
    func testGuardrailWithActorContext() async throws {
        // Given
        let context = AgentContext(input: "test input")

        let guardrail = ClosureInputGuardrail(name: "ContextGuardrail") { input, context in
            guard let ctx = context else {
                return .tripwire(message: "No context provided")
            }

            let originalInput = await ctx.get(.originalInput)
            if originalInput?.stringValue == "test input" {
                return .passed(message: "Context verified")
            }

            return .tripwire(message: "Context mismatch")
        }

        // When
        let result = try await guardrail.validate("input", context: context)

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == "Context verified")
    }
    
    @Test("Guardrail is Sendable in TaskGroup")
    func testGuardrailSendableInTaskGroup() async throws {
        // Given
        let guardrail = ClosureInputGuardrail(name: "TaskGroupGuardrail") { input, context in
            .passed(message: "Validated: \(input)")
        }
        
        // When
        let results = try await withThrowingTaskGroup(of: GuardrailResult.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try await guardrail.validate("input-\(i)", context: nil)
                }
            }
            
            var collected: [GuardrailResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
        
        // Then
        #expect(results.count == 5)
        #expect(results.allSatisfy { !$0.tripwireTriggered })
    }
    
    @Test("Guardrail can be stored in actor")
    func testGuardrailStoredInActor() async throws {
        // Given
        actor GuardrailStore {
            private var guardrails: [any InputGuardrail] = []
            
            func add(_ guardrail: any InputGuardrail) {
                guardrails.append(guardrail)
            }
            
            func execute(_ input: String, context: AgentContext?) async throws -> [GuardrailResult] {
                var results: [GuardrailResult] = []
                for guardrail in guardrails {
                    let result = try await guardrail.validate(input, context: context)
                    results.append(result)
                }
                return results
            }
        }
        
        let store = GuardrailStore()
        
        let guardrail1 = ClosureInputGuardrail(name: "Guard1") { input, context in
            .passed()
        }
        let guardrail2 = ClosureInputGuardrail(name: "Guard2") { input, context in
            .passed()
        }
        
        // When
        await store.add(guardrail1)
        await store.add(guardrail2)
        let results = try await store.execute("test", context: nil)
        
        // Then
        #expect(results.count == 2)
        #expect(results.allSatisfy { !$0.tripwireTriggered })
    }
    
    // MARK: - Edge Cases
    
    @Test("ClosureInputGuardrail handles empty input")
    func testClosureInputGuardrailEmptyInput() async throws {
        // Given
        actor InputCapture {
            var value: String?
            func set(_ newValue: String) { value = newValue }
            func get() -> String? { value }
        }

        let capture = InputCapture()
        let guardrail = ClosureInputGuardrail(name: "EmptyInputGuardrail") { input, context in
            await capture.set(input)
            return input.isEmpty ? .tripwire(message: "Empty input") : .passed()
        }

        // When
        let result = try await guardrail.validate("", context: nil)

        // Then
        let capturedInput = await capture.get()
        #expect(capturedInput == "")
        #expect(result.tripwireTriggered == true)
        #expect(result.message == "Empty input")
    }
    
    @Test("ClosureInputGuardrail handles very long input")
    func testClosureInputGuardrailLongInput() async throws {
        // Given
        let longInput = String(repeating: "a", count: 10000)
        let guardrail = ClosureInputGuardrail(name: "LongInputGuardrail") { input, context in
            .passed(message: "Length: \(input.count)")
        }
        
        // When
        let result = try await guardrail.validate(longInput, context: nil)
        
        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == "Length: 10000")
    }
    
    @Test("ClosureInputGuardrail handles special characters in input")
    func testClosureInputGuardrailSpecialCharacters() async throws {
        // Given
        let specialInput = "Test with émojis 🎉 and symbols !@#$%^&*()"

        actor InputCapture {
            var value: String?
            func set(_ newValue: String) { value = newValue }
            func get() -> String? { value }
        }

        let capture = InputCapture()
        let guardrail = ClosureInputGuardrail(name: "SpecialCharGuardrail") { input, context in
            await capture.set(input)
            return .passed()
        }

        // When
        _ = try await guardrail.validate(specialInput, context: nil)

        // Then
        let capturedInput = await capture.get()
        #expect(capturedInput == specialInput)
    }
}
