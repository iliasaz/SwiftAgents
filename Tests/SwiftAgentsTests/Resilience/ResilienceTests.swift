// ResilienceTests.swift
// SwiftAgents Framework
//
// Comprehensive tests for Phase 4 Resilience components using Swift Testing framework.

import Testing
import Foundation
@testable import SwiftAgents

// MARK: - Test Errors

enum TestError: Error, Equatable {
    case transient
    case permanent
    case network
    case timeout
}

// MARK: - Test Helpers (Thread-safe)

/// Thread-safe counter for testing async code
actor TestCounter {
    private var value: Int = 0
    
    func increment() -> Int {
        value += 1
        return value
    }
    
    func get() -> Int { value }
    
    func reset() { value = 0 }
}

/// Thread-safe array for tracking values
actor TestRecorder<T: Sendable> {
    private var items: [T] = []
    
    func append(_ item: T) {
        items.append(item)
    }
    
    func getAll() -> [T] { items }
    
    func count() -> Int { items.count }
}

/// Thread-safe boolean flag
actor TestFlag {
    private var value: Bool = false
    
    func set(_ newValue: Bool) {
        value = newValue
    }
    
    func get() -> Bool { value }
}

// MARK: - RetryPolicy Tests

@Suite("RetryPolicy Tests", .disabled("Requires Phase 4 concurrency fixes"))
struct RetryPolicyTests {
    
    // MARK: - Successful Execution Tests
    
    @Test("Successful execution without retry")
    func testSuccessfulExecutionWithoutRetry() async throws {
        let policy = RetryPolicy(maxAttempts: 3, backoff: .immediate)
        let counter = TestCounter()
        
        let result = try await policy.execute {
            _ = await counter.increment()
            return "success"
        }
        
        #expect(result == "success")
        #expect(await counter.get() == 1)
    }
    
    @Test("Immediate success with no retry attempts")
    func testImmediateSuccess() async throws {
        let policy = RetryPolicy.standard
        let counter = TestCounter()
        
        let result = try await policy.execute {
            _ = await counter.increment()
            return 42
        }
        
        #expect(result == 42)
        #expect(await counter.get() == 1)
    }
    
    // MARK: - Retry Until Success Tests
    
    @Test("Retry until success on transient errors")
    func testRetryUntilSuccess() async throws {
        let policy = RetryPolicy(maxAttempts: 3, backoff: .immediate)
        let counter = TestCounter()
        
        let result = try await policy.execute {
            let count = await counter.increment()
            if count < 3 {
                throw TestError.transient
            }
            return "success"
        }
        
        #expect(result == "success")
        #expect(await counter.get() == 3)
    }
    
    @Test("First retry succeeds after initial failure")
    func testFirstRetrySucceeds() async throws {
        let policy = RetryPolicy(maxAttempts: 2, backoff: .immediate)
        let counter = TestCounter()
        
        let result = try await policy.execute {
            let count = await counter.increment()
            if count == 1 {
                throw TestError.network
            }
            return "recovered"
        }
        
        #expect(result == "recovered")
        #expect(await counter.get() == 2)
    }
    
    // MARK: - Retry Exhaustion Tests
    
    @Test("Retry exhaustion throws ResilienceError.retriesExhausted")
    func testRetryExhaustion() async throws {
        let policy = RetryPolicy(maxAttempts: 2, backoff: .immediate)
        let counter = TestCounter()
        
        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw TestError.permanent
            }
            Issue.record("Should have thrown ResilienceError.retriesExhausted")
        } catch let error as ResilienceError {
            if case .retriesExhausted(let attempts, let lastError) = error {
                #expect(attempts == 3) // initial + 2 retries
                #expect(lastError.contains("permanent"))
            } else {
                Issue.record("Expected retriesExhausted, got \(error)")
            }
        }
        
        #expect(await counter.get() == 3)
    }
    
    @Test("All retries fail with consistent error")
    func testAllRetriesFail() async throws {
        let policy = RetryPolicy(maxAttempts: 3, backoff: .immediate)
        let counter = TestCounter()
        
        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw TestError.timeout
            }
            Issue.record("Expected error to be thrown")
        } catch let error as ResilienceError {
            #expect(error == .retriesExhausted(attempts: 4, lastError: "timeout"))
        }
        
        #expect(await counter.get() == 4) // initial + 3 retries
    }
    
    // MARK: - BackoffStrategy Tests
    
    @Test("BackoffStrategy.fixed returns constant delay")
    func testFixedBackoff() {
        let strategy = BackoffStrategy.fixed(delay: 1.5)
        
        #expect(strategy.delay(forAttempt: 1) == 1.5)
        #expect(strategy.delay(forAttempt: 2) == 1.5)
        #expect(strategy.delay(forAttempt: 5) == 1.5)
    }
    
    @Test("BackoffStrategy.exponential calculates correct delays")
    func testExponentialBackoff() {
        let strategy = BackoffStrategy.exponential(base: 1.0, multiplier: 2.0, maxDelay: 10.0)
        
        #expect(strategy.delay(forAttempt: 1) == 1.0)  // 1.0 * 2^0
        #expect(strategy.delay(forAttempt: 2) == 2.0)  // 1.0 * 2^1
        #expect(strategy.delay(forAttempt: 3) == 4.0)  // 1.0 * 2^2
        #expect(strategy.delay(forAttempt: 4) == 8.0)  // 1.0 * 2^3
        #expect(strategy.delay(forAttempt: 5) == 10.0) // capped at maxDelay
    }
    
    @Test("BackoffStrategy.linear calculates correct delays")
    func testLinearBackoff() {
        let strategy = BackoffStrategy.linear(initial: 1.0, increment: 0.5, maxDelay: 5.0)
        
        #expect(strategy.delay(forAttempt: 1) == 1.0)  // 1.0 + 0.5 * 0
        #expect(strategy.delay(forAttempt: 2) == 1.5)  // 1.0 + 0.5 * 1
        #expect(strategy.delay(forAttempt: 3) == 2.0)  // 1.0 + 0.5 * 2
        #expect(strategy.delay(forAttempt: 10) == 5.0) // capped at maxDelay
    }
    
    @Test("BackoffStrategy.immediate returns zero delay")
    func testImmediateBackoff() {
        let strategy = BackoffStrategy.immediate
        
        #expect(strategy.delay(forAttempt: 1) == 0)
        #expect(strategy.delay(forAttempt: 100) == 0)
    }
    
    @Test("BackoffStrategy.custom uses provided calculator")
    func testCustomBackoff() {
        let strategy = BackoffStrategy.custom { attempt in
            Double(attempt) * 10.0
        }
        
        #expect(strategy.delay(forAttempt: 1) == 10.0)
        #expect(strategy.delay(forAttempt: 2) == 20.0)
        #expect(strategy.delay(forAttempt: 5) == 50.0)
    }
    
    // MARK: - shouldRetry Predicate Tests
    
    @Test("shouldRetry predicate controls retry behavior")
    func testShouldRetryPredicate() async throws {
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .immediate,
            shouldRetry: { error in
                // Only retry transient errors
                if let testError = error as? TestError {
                    return testError == .transient
                }
                return false
            }
        )
        let counter = TestCounter()
        
        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw TestError.permanent
            }
            Issue.record("Should have thrown error")
        } catch let error as TestError {
            #expect(error == .permanent)
        }
        
        // Should not retry because shouldRetry returned false
        #expect(await counter.get() == 1)
    }
    
    @Test("shouldRetry allows selective error retry")
    func testSelectiveRetry() async throws {
        let transientCounter = TestCounter()
        let permanentCounter = TestCounter()
        
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .immediate,
            shouldRetry: { error in
                (error as? TestError) == .transient
            }
        )
        
        // Test with transient error - should retry
        do {
            _ = try await policy.execute {
                _ = await transientCounter.increment()
                throw TestError.transient
            }
        } catch {
            // Expected to exhaust retries
        }
        #expect(await transientCounter.get() == 4) // initial + 3 retries
        
        // Test with permanent error - should not retry
        do {
            _ = try await policy.execute {
                _ = await permanentCounter.increment()
                throw TestError.permanent
            }
        } catch {
            // Expected to fail immediately
        }
        #expect(await permanentCounter.get() == 1) // no retries
    }
    
    // MARK: - onRetry Callback Tests
    
    @Test("onRetry callback is invoked before each retry")
    func testOnRetryCallback() async throws {
        let recorder = TestRecorder<(Int, String)>()
        
        let policy = RetryPolicy(
            maxAttempts: 2,
            backoff: .immediate,
            onRetry: { attempt, error in
                await recorder.append((attempt, "\(error)"))
            }
        )
        let counter = TestCounter()
        
        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw TestError.network
            }
        } catch {
            // Expected
        }
        
        let callbacks = await recorder.getAll()
        #expect(callbacks.count == 2)
        #expect(callbacks[0].0 == 1)
        #expect(callbacks[1].0 == 2)
    }
    
    // MARK: - Static Convenience Tests
    
    @Test("Static noRetry policy fails immediately")
    func testNoRetryPolicy() async throws {
        let counter = TestCounter()
        
        do {
            _ = try await RetryPolicy.noRetry.execute {
                _ = await counter.increment()
                throw TestError.transient
            }
            Issue.record("Should have thrown error")
        } catch {
            // Expected
        }
        
        #expect(await counter.get() == 1)
    }
    
    @Test("Static standard policy has correct configuration")
    func testStandardPolicy() {
        let policy = RetryPolicy.standard
        #expect(policy.maxAttempts == 3)
        #expect(policy.backoff == .exponential(base: 1.0, multiplier: 2.0, maxDelay: 60.0))
    }
    
    @Test("Static aggressive policy has correct configuration")
    func testAggressivePolicy() {
        let policy = RetryPolicy.aggressive
        #expect(policy.maxAttempts == 5)
        #expect(policy.backoff == .exponentialWithJitter(base: 0.5, multiplier: 2.0, maxDelay: 30.0))
    }
}

// MARK: - CircuitBreaker Tests

@Suite("CircuitBreaker Tests", .disabled("Requires Phase 4 concurrency fixes"))
struct CircuitBreakerTests {
    
    // MARK: - Initial State Tests
    
    @Test("Initial state is closed")
    func testInitialStateClosed() async {
        let breaker = CircuitBreaker(name: "test")
        let state = await breaker.currentState()
        #expect(state == .closed)
    }
    
    @Test("Initial state allows requests")
    func testInitialStateAllowsRequests() async {
        let breaker = CircuitBreaker(name: "test")
        let isAllowing = await breaker.isAllowingRequests()
        #expect(isAllowing == true)
    }
    
    // MARK: - Circuit Opening Tests
    
    @Test("Circuit opens after failureThreshold failures")
    func testCircuitOpensAfterFailures() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 3,
            resetTimeout: 60.0
        )
        
        // Execute 3 failing operations
        for _ in 1...3 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }
        
        // Circuit should now be open
        let state = await breaker.currentState()
        if case .open = state {
            // Success
        } else {
            Issue.record("Expected circuit to be open, got \(state)")
        }
    }
    
    @Test("Circuit remains closed below failureThreshold")
    func testCircuitRemainsClosedBelowThreshold() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 5,
            resetTimeout: 60.0
        )
        
        // Execute 3 failing operations (below threshold)
        for _ in 1...3 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }
        
        let state = await breaker.currentState()
        #expect(state == .closed)
    }
    
    @Test("Open circuit throws circuitBreakerOpen error")
    func testOpenCircuitThrowsError() async throws {
        let breaker = CircuitBreaker(
            name: "payment-service",
            failureThreshold: 2,
            resetTimeout: 60.0
        )
        
        // Trigger circuit open
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }
        
        // Next request should fail with circuitBreakerOpen
        do {
            _ = try await breaker.execute {
                return "success"
            }
            Issue.record("Should have thrown circuitBreakerOpen")
        } catch let error as ResilienceError {
            if case .circuitBreakerOpen(let serviceName) = error {
                #expect(serviceName == "payment-service")
            } else {
                Issue.record("Expected circuitBreakerOpen, got \(error)")
            }
        }
    }
    
    // MARK: - Half-Open Transition Tests
    
    @Test("Circuit transitions to halfOpen after timeout")
    func testCircuitTransitionsToHalfOpen() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 0.1 // Short timeout for testing
        )
        
        // Open the circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }
        
        // Verify circuit is open
        var state = await breaker.currentState()
        if case .open = state {
            // Good
        } else {
            Issue.record("Expected circuit to be open")
        }
        
        // Wait for timeout
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        // Trigger state check by attempting execution
        do {
            _ = try await breaker.execute {
                // This will check state and transition to half-open
                return "test"
            }
        } catch {
            // May fail depending on timing
        }
        
        state = await breaker.currentState()
        // Should be halfOpen or closed (if the test operation succeeded)
        #expect(state == .halfOpen || state == .closed)
    }
    
    // MARK: - Circuit Closing Tests
    
    @Test("Circuit closes after successThreshold successes in halfOpen")
    func testCircuitClosesAfterSuccesses() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            successThreshold: 2,
            resetTimeout: 0.1,
            halfOpenMaxRequests: 5
        )
        
        // Open the circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }
        
        // Wait for timeout to transition to half-open
        try await Task.sleep(nanoseconds: 150_000_000)
        
        // Execute successful operations to close circuit
        for _ in 1...2 {
            _ = try await breaker.execute {
                return "success"
            }
        }
        
        let state = await breaker.currentState()
        #expect(state == .closed)
    }
    
    @Test("Single success in halfOpen keeps circuit halfOpen")
    func testSingleSuccessInHalfOpen() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            successThreshold: 3,
            resetTimeout: 0.1
        )
        
        // Open circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch { }
        }
        
        // Wait and transition to half-open
        try await Task.sleep(nanoseconds: 150_000_000)
        
        // One success
        _ = try await breaker.execute { return "success" }
        
        let state = await breaker.currentState()
        #expect(state == .halfOpen)
    }
    
    // MARK: - Manual Control Tests
    
    @Test("Manual reset closes circuit")
    func testManualReset() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 60.0
        )
        
        // Open the circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }
        
        // Manually reset
        await breaker.reset()
        
        let state = await breaker.currentState()
        #expect(state == .closed)
    }
    
    @Test("Manual trip opens circuit")
    func testManualTrip() async throws {
        let breaker = CircuitBreaker(name: "test")
        
        // Initially closed
        var state = await breaker.currentState()
        #expect(state == .closed)
        
        // Manually trip
        await breaker.trip()
        
        state = await breaker.currentState()
        if case .open = state {
            // Success
        } else {
            Issue.record("Expected circuit to be open after trip()")
        }
    }
    
    // MARK: - Statistics Tests
    
    @Test("Statistics track success and failure counts")
    func testStatistics() async throws {
        let breaker = CircuitBreaker(name: "test-service")
        
        // Execute some successful operations
        for _ in 1...3 {
            _ = try await breaker.execute {
                return "success"
            }
        }
        
        // Execute some failures
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }
        
        let stats = await breaker.statistics()
        #expect(stats.name == "test-service")
        #expect(stats.successCount == 3)
        #expect(stats.failureCount == 2)
        #expect(stats.lastFailureTime != nil)
    }
    
    @Test("Statistics calculate success rate correctly")
    func testSuccessRate() async throws {
        let breaker = CircuitBreaker(name: "test")
        
        // 3 successes, 1 failure = 75% success rate
        _ = try await breaker.execute { return "ok" }
        _ = try await breaker.execute { return "ok" }
        _ = try await breaker.execute { return "ok" }
        do {
            _ = try await breaker.execute { throw TestError.network }
        } catch { }
        
        let stats = await breaker.statistics()
        let rate = stats.successRate ?? 0.0
        #expect(abs(rate - 0.75) < 0.01)
    }
    
    // MARK: - HalfOpen Request Limiting Tests
    
    @Test("HalfOpen state limits concurrent requests")
    func testHalfOpenRequestLimit() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 0.1,
            halfOpenMaxRequests: 1
        )
        
        // Open circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch { }
        }
        
        // Wait for half-open transition
        try await Task.sleep(nanoseconds: 150_000_000)
        
        // First request should be allowed
        let task = Task {
            try await breaker.execute {
                try await Task.sleep(nanoseconds: 100_000_000) // Slow operation
                return "success"
            }
        }
        
        // Give it time to start
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Second concurrent request should be blocked
        do {
            _ = try await breaker.execute {
                return "should fail"
            }
            Issue.record("Second request should have been blocked")
        } catch let error as ResilienceError {
            if case .circuitBreakerOpen = error {
                // Expected
            } else {
                Issue.record("Expected circuitBreakerOpen")
            }
        }
        
        // Clean up
        _ = try await task.value
    }
}

// MARK: - CircuitBreakerRegistry Tests

@Suite("CircuitBreakerRegistry Tests", .disabled("Requires Phase 4 concurrency fixes"))
struct CircuitBreakerRegistryTests {
    
    @Test("Registry creates and returns circuit breakers")
    func testRegistryCreatesBreakers() async {
        let registry = CircuitBreakerRegistry()
        
        let breaker1 = await registry.breaker(named: "api")
        let breaker2 = await registry.breaker(named: "database")
        
        let stats1 = await breaker1.statistics()
        let stats2 = await breaker2.statistics()
        
        #expect(stats1.name == "api")
        #expect(stats2.name == "database")
    }
    
    @Test("Registry returns same instance for same name")
    func testRegistryReturnsSameInstance() async {
        let registry = CircuitBreakerRegistry()
        
        let breaker1 = await registry.breaker(named: "service")
        let breaker2 = await registry.breaker(named: "service")
        
        // Should be the same instance
        let stats1 = await breaker1.statistics()
        let stats2 = await breaker2.statistics()
        
        #expect(stats1.name == stats2.name)
    }
    
    @Test("Registry applies custom configuration")
    func testRegistryCustomConfiguration() async throws {
        let registry = CircuitBreakerRegistry()
        
        let breaker = await registry.breaker(named: "custom") { config in
            config.failureThreshold = 10
        }
        
        // Verify threshold by testing it
        for _ in 1...9 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch { }
        }
        
        let state = await breaker.currentState()
        #expect(state == .closed) // Should still be closed with 9 failures
    }
    
    @Test("Registry resetAll resets all breakers")
    func testRegistryResetAll() async throws {
        let registry = CircuitBreakerRegistry()
        
        let breaker1 = await registry.breaker(named: "service1")
        let breaker2 = await registry.breaker(named: "service2")
        
        // Trip both breakers
        await breaker1.trip()
        await breaker2.trip()
        
        // Reset all
        await registry.resetAll()
        
        let state1 = await breaker1.currentState()
        let state2 = await breaker2.currentState()
        
        #expect(state1 == .closed)
        #expect(state2 == .closed)
    }
}

// MARK: - FallbackChain Tests

@Suite("FallbackChain Tests", .disabled("Requires Phase 4 concurrency fixes"))
struct FallbackChainTests {
    
    // MARK: - Success Tests
    
    @Test("First attempt succeeds without fallback")
    func testFirstAttemptSucceeds() async throws {
        let primaryFlag = TestFlag()
        let fallbackFlag = TestFlag()
        
        let result = try await FallbackChain<String>()
            .attempt(name: "Primary") {
                await primaryFlag.set(true)
                return "primary-result"
            }
            .attempt(name: "Fallback") {
                await fallbackFlag.set(true)
                return "fallback-result"
            }
            .execute()
        
        #expect(result == "primary-result")
        #expect(await primaryFlag.get() == true)
        #expect(await fallbackFlag.get() == false)
    }
    
    @Test("Immediate success with single step")
    func testImmediateSingleStepSuccess() async throws {
        let chain = FallbackChain<Int>()
            .attempt(name: "Only") {
                return 42
            }
        
        let result = try await chain.execute()
        #expect(result == 42)
    }
    
    // MARK: - Fallback Tests
    
    @Test("Fallback to second option on failure")
    func testFallbackOnFailure() async throws {
        let primaryFlag = TestFlag()
        let secondaryFlag = TestFlag()
        
        let result = try await FallbackChain<String>()
            .attempt(name: "Primary") {
                await primaryFlag.set(true)
                throw TestError.network
            }
            .attempt(name: "Secondary") {
                await secondaryFlag.set(true)
                return "secondary-success"
            }
            .execute()
        
        #expect(result == "secondary-success")
        #expect(await primaryFlag.get() == true)
        #expect(await secondaryFlag.get() == true)
    }
    
    @Test("Multiple fallbacks cascade correctly")
    func testMultipleFallbacksCascade() async throws {
        let recorder = TestRecorder<String>()
        
        let result = try await FallbackChain<String>()
            .attempt(name: "First") {
                await recorder.append("first")
                throw TestError.network
            }
            .attempt(name: "Second") {
                await recorder.append("second")
                throw TestError.timeout
            }
            .attempt(name: "Third") {
                await recorder.append("third")
                return "third-success"
            }
            .execute()
        
        #expect(result == "third-success")
        #expect(await recorder.getAll() == ["first", "second", "third"])
    }
    
    // MARK: - All Fallbacks Fail Tests
    
    @Test("All fallbacks fail throws ResilienceError.allFallbacksFailed")
    func testAllFallbacksFail() async throws {
        do {
            _ = try await FallbackChain<String>()
                .attempt(name: "First") {
                    throw TestError.network
                }
                .attempt(name: "Second") {
                    throw TestError.timeout
                }
                .execute()
            
            Issue.record("Should have thrown allFallbacksFailed")
        } catch let error as ResilienceError {
            if case .allFallbacksFailed(let errors) = error {
                #expect(errors.count == 2)
                #expect(errors[0].contains("First"))
                #expect(errors[1].contains("Second"))
            } else {
                Issue.record("Expected allFallbacksFailed, got \(error)")
            }
        }
    }
    
    @Test("Empty chain throws allFallbacksFailed")
    func testEmptyChainFails() async throws {
        let chain = FallbackChain<String>()
        
        do {
            _ = try await chain.execute()
            Issue.record("Should have thrown error")
        } catch let error as ResilienceError {
            if case .allFallbacksFailed(let errors) = error {
                #expect(errors.count == 1)
                #expect(errors[0].contains("No steps configured"))
            } else {
                Issue.record("Expected allFallbacksFailed")
            }
        }
    }
    
    // MARK: - Final Fallback Tests
    
    @Test("Final fallback always succeeds with value")
    func testFinalFallbackValue() async throws {
        let result = try await FallbackChain<String>()
            .attempt(name: "Primary") {
                throw TestError.network
            }
            .attempt(name: "Secondary") {
                throw TestError.timeout
            }
            .fallback(name: "Default", "fallback-value")
            .execute()
        
        #expect(result == "fallback-value")
    }
    
    @Test("Final fallback always succeeds with operation")
    func testFinalFallbackOperation() async throws {
        let flag = TestFlag()
        
        let result = try await FallbackChain<Int>()
            .attempt(name: "Primary") {
                throw TestError.network
            }
            .fallback(name: "Cache") {
                await flag.set(true)
                return 999
            }
            .execute()
        
        #expect(result == 999)
        #expect(await flag.get() == true)
    }
    
    // MARK: - executeWithResult Tests
    
    @Test("executeWithResult returns diagnostic info")
    func testExecuteWithResultDiagnostics() async throws {
        let result = try await FallbackChain<String>()
            .attempt(name: "Primary") {
                throw TestError.network
            }
            .attempt(name: "Secondary") {
                throw TestError.timeout
            }
            .attempt(name: "Tertiary") {
                return "success"
            }
            .executeWithResult()
        
        #expect(result.output == "success")
        #expect(result.stepName == "Tertiary")
        #expect(result.stepIndex == 2)
        #expect(result.totalAttempts == 3)
        #expect(result.errors.count == 2)
    }
    
    @Test("executeWithResult captures error details")
    func testExecuteWithResultErrorDetails() async throws {
        let result = try await FallbackChain<String>()
            .attempt(name: "First") {
                throw TestError.network
            }
            .attempt(name: "Second") {
                return "ok"
            }
            .executeWithResult()
        
        #expect(result.errors.count == 1)
        #expect(result.errors[0].stepName == "First")
        #expect(result.errors[0].stepIndex == 0)
    }
    
    @Test("executeWithResult with immediate success has no errors")
    func testExecuteWithResultNoErrors() async throws {
        let result = try await FallbackChain<String>()
            .attempt(name: "Only") {
                return "success"
            }
            .executeWithResult()
        
        #expect(result.totalAttempts == 1)
        #expect(result.errors.isEmpty)
    }
    
    // MARK: - Conditional Fallback Tests
    
    @Test("Conditional fallback with attemptIf")
    func testConditionalFallbackTrue() async throws {
        let shouldUseSecondary = true  // Use let for constants
        
        let result = try await FallbackChain<String>()
            .attempt(name: "Primary") {
                throw TestError.network
            }
            .attemptIf(name: "Conditional", condition: {
                return shouldUseSecondary
            }) {
                return "conditional-success"
            }
            .execute()
        
        #expect(result == "conditional-success")
    }
    
    @Test("Conditional fallback skipped when condition false")
    func testConditionalFallbackFalse() async throws {
        let shouldSkip = false  // Use let for constants
        
        let result = try await FallbackChain<String>()
            .attempt(name: "Primary") {
                throw TestError.network
            }
            .attemptIf(name: "Conditional", condition: {
                return shouldSkip
            }) {
                Issue.record("This should not be called")
                return "should-not-happen"
            }
            .fallback(name: "Final", "default")
            .execute()
        
        #expect(result == "default")
    }
    
    // MARK: - onFailure Callback Tests
    
    @Test("onFailure callback invoked for each failure")
    func testOnFailureCallback() async throws {
        let recorder = TestRecorder<String>()
        
        _ = try await FallbackChain<String>()
            .attempt(name: "First") {
                throw TestError.network
            }
            .attempt(name: "Second") {
                throw TestError.timeout
            }
            .attempt(name: "Third") {
                return "success"
            }
            .onFailure { stepName, error in
                await recorder.append(stepName)
            }
            .execute()
        
        #expect(await recorder.getAll() == ["First", "Second"])
    }
    
    @Test("onFailure not called on success")
    func testOnFailureNotCalledOnSuccess() async throws {
        let flag = TestFlag()
        
        _ = try await FallbackChain<String>()
            .attempt(name: "Primary") {
                return "success"
            }
            .onFailure { _, _ in
                await flag.set(true)
            }
            .execute()
        
        #expect(await flag.get() == false)
    }
    
    // MARK: - Static Convenience Tests
    
    @Test("Static from constructor creates chain")
    func testStaticFromConstructor() async throws {
        let result = try await FallbackChain.from(
            (name: "First", operation: {
                throw TestError.network
            }),
            (name: "Second", operation: {
                return "second-result"
            })
        ).execute()
        
        #expect(result == "second-result")
    }
}

// MARK: - Integration Tests

@Suite("Resilience Integration Tests", .disabled("Requires Phase 4 concurrency fixes"))
struct ResilienceIntegrationTests {
    
    @Test("RetryPolicy with CircuitBreaker integration")
    func testRetryWithCircuitBreaker() async throws {
        let breaker = CircuitBreaker(
            name: "api",
            failureThreshold: 3,
            resetTimeout: 0.1
        )
        
        let policy = RetryPolicy(
            maxAttempts: 2,
            backoff: .immediate
        )
        
        let counter = TestCounter()
        
        // Execute with both retry and circuit breaker
        do {
            _ = try await policy.execute {
                try await breaker.execute {
                    _ = await counter.increment()
                    throw TestError.network
                }
            }
        } catch {
            // Expected to fail
        }
        
        // Should have attempted: initial + 2 retries = 3 times
        // Circuit should be open now
        let state = await breaker.currentState()
        if case .open = state {
            // Success
        } else {
            Issue.record("Expected circuit to be open")
        }
    }
    
    @Test("FallbackChain with RetryPolicy per step")
    func testFallbackWithRetryPerStep() async throws {
        let primaryCounter = TestCounter()
        let secondaryCounter = TestCounter()
        
        let policy = RetryPolicy(maxAttempts: 2, backoff: .immediate)
        
        let result = try await FallbackChain<String>()
            .attempt(name: "Primary") {
                try await policy.execute {
                    _ = await primaryCounter.increment()
                    throw TestError.transient
                }
            }
            .attempt(name: "Secondary") {
                try await policy.execute {
                    let count = await secondaryCounter.increment()
                    if count < 2 {
                        throw TestError.transient
                    }
                    return "secondary-success"
                }
            }
            .execute()
        
        #expect(result == "secondary-success")
        #expect(await primaryCounter.get() == 3) // initial + 2 retries
        #expect(await secondaryCounter.get() == 2) // initial + 1 retry
    }
}
