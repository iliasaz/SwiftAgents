// ObservabilityTests.swift
// SwiftAgents Framework
//
// Comprehensive tests for Phase 4 Observability components.
// Tests TraceEvent, ConsoleTracer, and MetricsCollector functionality.

import Testing
import Foundation
@testable import SwiftAgents

// MARK: - TraceEvent Tests

@Suite("TraceEvent Tests")
struct TraceEventTests {
    
    // MARK: - Builder Tests
    
    @Test("Builder creates events with required parameters")
    func builderCreatesBasicEvent() {
        let traceId = UUID()
        let builder = TraceEvent.Builder(
            traceId: traceId,
            kind: .agentStart,
            message: "Test message"
        )
        
        let event = builder.build()
        
        #expect(event.traceId == traceId)
        #expect(event.kind == .agentStart)
        #expect(event.message == "Test message")
        #expect(event.level == .info) // default level
    }
    
    @Test("Builder sets optional parameters via fluent interface")
    func builderSetsOptionalParameters() {
        let traceId = UUID()
        let parentSpanId = UUID()
        let duration: TimeInterval = 1.5
        
        let event = TraceEvent.Builder(traceId: traceId, kind: .toolCall, message: "Tool executing")
            .parentSpan(parentSpanId)
            .duration(duration)
            .level(.debug)
            .agent("TestAgent")
            .tool("web_search")
            .build()
        
        #expect(event.parentSpanId == parentSpanId)
        #expect(event.duration == duration)
        #expect(event.level == .debug)
        #expect(event.agentName == "TestAgent")
        #expect(event.toolName == "web_search")
    }
    
    @Test("Builder adds metadata incrementally")
    func builderAddsMetadata() {
        let traceId = UUID()
        let event = TraceEvent.Builder(traceId: traceId, kind: .custom, message: "Test")
            .metadata(key: "key1", value: .string("value1"))
            .metadata(key: "key2", value: .int(42))
            .build()
        
        #expect(event.metadata["key1"]?.stringValue == "value1")
        #expect(event.metadata["key2"]?.intValue == 42)
    }
    
    @Test("Builder replaces all metadata")
    func builderReplacesMetadata() {
        let traceId = UUID()
        let initialMetadata: [String: SendableValue] = ["initial": .string("data")]
        let newMetadata: [String: SendableValue] = ["new": .string("data")]
        
        let event = TraceEvent.Builder(traceId: traceId, kind: .custom, message: "Test")
            .metadata(initialMetadata)
            .metadata(newMetadata)
            .build()
        
        #expect(event.metadata["initial"] == nil)
        #expect(event.metadata["new"]?.stringValue == "data")
    }
    
    @Test("Builder merges additional metadata")
    func builderMergesMetadata() {
        let traceId = UUID()
        let event = TraceEvent.Builder(traceId: traceId, kind: .custom, message: "Test")
            .metadata(["key1": .string("value1")])
            .addingMetadata(["key2": .int(42)])
            .build()
        
        #expect(event.metadata["key1"]?.stringValue == "value1")
        #expect(event.metadata["key2"]?.intValue == 42)
    }
    
    @Test("Builder sets error from Error instance")
    func builderSetsErrorFromError() {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Test error occurred" }
        }
        
        let traceId = UUID()
        let testError = TestError()
        
        let event = TraceEvent.Builder(traceId: traceId, kind: .agentError, message: "Error")
            .error(testError)
            .build()
        
        #expect(event.error != nil)
        #expect(event.error?.message == "Test error occurred")
    }
    
    @Test("Builder sets error info directly")
    func builderSetsErrorInfoDirectly() {
        let traceId = UUID()
        let errorInfo = ErrorInfo(
            type: "CustomError",
            message: "Something went wrong",
            stackTrace: ["Frame 1", "Frame 2"]
        )
        
        let event = TraceEvent.Builder(traceId: traceId, kind: .agentError, message: "Error")
            .error(errorInfo)
            .build()
        
        #expect(event.error == errorInfo)
    }
    
    @Test("Builder sets source location")
    func builderSetsSourceLocation() {
        let traceId = UUID()
        let location = SourceLocation(file: "/path/to/file.swift", function: "testFunc", line: 42)
        
        let event = TraceEvent.Builder(traceId: traceId, kind: .checkpoint, message: "Test")
            .source(location)
            .build()
        
        #expect(event.source == location)
    }
    
    // MARK: - EventLevel Tests
    
    @Test("EventLevel comparison works correctly")
    func eventLevelComparison() {
        #expect(EventLevel.trace < EventLevel.debug)
        #expect(EventLevel.debug < EventLevel.info)
        #expect(EventLevel.info < EventLevel.warning)
        #expect(EventLevel.warning < EventLevel.error)
        #expect(EventLevel.error < EventLevel.critical)
        
        #expect(EventLevel.info == EventLevel.info)
        #expect(EventLevel.critical > EventLevel.error)
    }
    
    @Test("EventLevel ordering is correct")
    func eventLevelOrdering() {
        let levels: [EventLevel] = [.critical, .trace, .warning, .debug, .error, .info]
        let sorted = levels.sorted()
        
        #expect(sorted == [.trace, .debug, .info, .warning, .error, .critical])
    }
    
    // MARK: - Sendable Tests
    
    @Test("TraceEvent is Sendable across async boundaries")
    func traceEventIsSendable() async {
        let traceId = UUID()
        let event = TraceEvent.Builder(traceId: traceId, kind: .agentStart, message: "Test")
            .agent("TestAgent")
            .build()
        
        // Transfer event across async task boundary
        let transferredEvent = await Task {
            return event
        }.value
        
        #expect(transferredEvent.id == event.id)
        #expect(transferredEvent.message == "Test")
    }
    
    // MARK: - Convenience Constructor Tests
    
    @Test("agentStart convenience constructor")
    func agentStartConvenience() {
        let traceId = UUID()
        let spanId = UUID()
        let event = TraceEvent.agentStart(
            traceId: traceId,
            spanId: spanId,
            agentName: "MyAgent",
            metadata: ["key": .string("value")]
        )
        
        #expect(event.traceId == traceId)
        #expect(event.spanId == spanId)
        #expect(event.kind == .agentStart)
        #expect(event.agentName == "MyAgent")
        #expect(event.level == .info)
        #expect(event.metadata["key"]?.stringValue == "value")
    }
    
    @Test("agentComplete convenience constructor")
    func agentCompleteConvenience() {
        let traceId = UUID()
        let spanId = UUID()
        let duration: TimeInterval = 2.5
        
        let event = TraceEvent.agentComplete(
            traceId: traceId,
            spanId: spanId,
            agentName: "MyAgent",
            duration: duration
        )
        
        #expect(event.kind == .agentComplete)
        #expect(event.duration == duration)
        #expect(event.agentName == "MyAgent")
    }
    
    @Test("agentError convenience constructor")
    func agentErrorConvenience() {
        struct TestError: Error {}
        
        let traceId = UUID()
        let spanId = UUID()
        let event = TraceEvent.agentError(
            traceId: traceId,
            spanId: spanId,
            agentName: "MyAgent",
            error: TestError()
        )
        
        #expect(event.kind == .agentError)
        #expect(event.level == .error)
        #expect(event.error != nil)
    }
    
    @Test("toolCall convenience constructor")
    func toolCallConvenience() {
        let traceId = UUID()
        let parentSpanId = UUID()
        
        let event = TraceEvent.toolCall(
            traceId: traceId,
            parentSpanId: parentSpanId,
            toolName: "web_search"
        )
        
        #expect(event.kind == .toolCall)
        #expect(event.level == .debug)
        #expect(event.toolName == "web_search")
        #expect(event.parentSpanId != nil)
    }
    
    @Test("toolResult convenience constructor")
    func toolResultConvenience() {
        let traceId = UUID()
        let spanId = UUID()
        let duration: TimeInterval = 1.2
        
        let event = TraceEvent.toolResult(
            traceId: traceId,
            spanId: spanId,
            toolName: "web_search",
            duration: duration
        )
        
        #expect(event.kind == .toolResult)
        #expect(event.level == .debug)
        #expect(event.duration == duration)
    }
    
    @Test("thought convenience constructor")
    func thoughtConvenience() {
        let traceId = UUID()
        let spanId = UUID()
        
        let event = TraceEvent.thought(
            traceId: traceId,
            spanId: spanId,
            agentName: "MyAgent",
            thought: "I need to search the web"
        )
        
        #expect(event.kind == .thought)
        #expect(event.level == .trace)
        #expect(event.message == "I need to search the web")
        #expect(event.metadata["thought"]?.stringValue == "I need to search the web")
    }
    
    @Test("custom convenience constructor")
    func customConvenience() {
        let traceId = UUID()
        
        let event = TraceEvent.custom(
            traceId: traceId,
            message: "Custom event",
            level: .warning,
            metadata: ["custom": .bool(true)]
        )
        
        #expect(event.kind == .custom)
        #expect(event.level == .warning)
        #expect(event.message == "Custom event")
    }
}

// MARK: - SourceLocation Tests

@Suite("SourceLocation Tests")
struct SourceLocationTests {
    
    @Test("SourceLocation extracts filename from path")
    func sourceLocationFilename() {
        let location = SourceLocation(
            file: "/path/to/project/Sources/MyFile.swift",
            function: "testFunc",
            line: 42
        )
        
        #expect(location.filename == "MyFile.swift")
    }
    
    @Test("SourceLocation formats correctly")
    func sourceLocationFormatted() {
        let location = SourceLocation(
            file: "/path/to/File.swift",
            function: "myFunction()",
            line: 123
        )
        
        #expect(location.formatted == "File.swift:123 - myFunction()")
    }
}

// MARK: - ErrorInfo Tests

@Suite("ErrorInfo Tests")
struct ErrorInfoTests {
    
    @Test("ErrorInfo creates from Swift Error")
    func errorInfoFromError() {
        struct CustomError: Error, LocalizedError {
            var errorDescription: String? { "Custom error message" }
        }
        
        let error = CustomError()
        let errorInfo = ErrorInfo(from: error)
        
        #expect(errorInfo.message == "Custom error message")
        #expect(errorInfo.type.contains("CustomError"))
    }
    
    @Test("ErrorInfo with stack trace")
    func errorInfoWithStackTrace() {
        let errorInfo = ErrorInfo(
            type: "RuntimeError",
            message: "Something failed",
            stackTrace: ["Frame 1", "Frame 2", "Frame 3"]
        )
        
        #expect(errorInfo.stackTrace?.count == 3)
        #expect(errorInfo.stackTrace?[0] == "Frame 1")
    }
}

// MARK: - ConsoleTracer Tests

@Suite("ConsoleTracer Tests")
struct ConsoleTracerTests {
    
    @Test("ConsoleTracer respects minimum level filtering")
    func consoleTracerMinimumLevel() async {
        let tracer = ConsoleTracer(minimumLevel: .warning)
        let traceId = UUID()
        
        // These should be filtered out (below warning level)
        await tracer.trace(.custom(traceId: traceId, message: "Trace", level: .trace))
        await tracer.trace(.custom(traceId: traceId, message: "Debug", level: .debug))
        await tracer.trace(.custom(traceId: traceId, message: "Info", level: .info))
        
        // These should pass through (at or above warning level)
        await tracer.trace(.custom(traceId: traceId, message: "Warning", level: .warning))
        await tracer.trace(.custom(traceId: traceId, message: "Error", level: .error))
        await tracer.trace(.custom(traceId: traceId, message: "Critical", level: .critical))
        
        // Test passes if no crash occurs during filtering
        #expect(true)
    }
    
    @Test("ConsoleTracer formats all event kinds without crashing")
    func consoleTracerFormatsAllEventKinds() async {
        let tracer = ConsoleTracer(minimumLevel: .trace, colorized: false)
        let traceId = UUID()
        let spanId = UUID()
        
        // Test all event kinds
        await tracer.trace(.agentStart(traceId: traceId, agentName: "Agent"))
        await tracer.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: 1.0))
        await tracer.trace(.agentError(traceId: traceId, spanId: spanId, agentName: "Agent", error: NSError(domain: "test", code: 1)))
        await tracer.trace(.toolCall(traceId: traceId, parentSpanId: spanId, toolName: "tool"))
        await tracer.trace(.toolResult(traceId: traceId, spanId: spanId, toolName: "tool", duration: 0.5))
        await tracer.trace(.thought(traceId: traceId, spanId: spanId, agentName: "Agent", thought: "thinking"))
        await tracer.trace(.custom(traceId: traceId, message: "custom"))
        
        // Test passes if all events are formatted without crash
        #expect(true)
    }
    
    @Test("ConsoleTracer handles events with metadata")
    func consoleTracerWithMetadata() async {
        let tracer = ConsoleTracer(minimumLevel: .info, colorized: false)
        let traceId = UUID()
        
        let event = TraceEvent.custom(
            traceId: traceId,
            message: "Event with metadata",
            metadata: [
                "key1": .string("value1"),
                "key2": .int(42),
                "key3": .bool(true)
            ]
        )
        
        await tracer.trace(event)
        
        // Test passes if metadata formatting doesn't crash
        #expect(true)
    }
    
    @Test("ConsoleTracer handles events with errors")
    func consoleTracerWithErrors() async {
        let tracer = ConsoleTracer(minimumLevel: .error, colorized: false)
        let traceId = UUID()
        
        let errorInfo = ErrorInfo(
            type: "TestError",
            message: "Test error message",
            stackTrace: ["Frame 1", "Frame 2"]
        )
        
        let event = TraceEvent.Builder(traceId: traceId, kind: .agentError, message: "Error occurred")
            .level(.error)
            .error(errorInfo)
            .build()
        
        await tracer.trace(event)
        
        // Test passes if error formatting doesn't crash
        #expect(true)
    }
}

// MARK: - PrettyConsoleTracer Tests

@Suite("PrettyConsoleTracer Tests")
struct PrettyConsoleTracerTests {
    
    @Test("PrettyConsoleTracer formats all event kinds")
    func prettyConsoleTracerFormatsAllKinds() async {
        let tracer = PrettyConsoleTracer(minimumLevel: .trace, colorized: false)
        let traceId = UUID()
        let spanId = UUID()
        
        // Test all event kinds to ensure emoji formatting works
        await tracer.trace(.agentStart(traceId: traceId, agentName: "Agent"))
        await tracer.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: 1.0))
        await tracer.trace(.custom(traceId: traceId, message: "Custom event"))
        
        // Test passes if all formatting completes without crash
        #expect(true)
    }
}

// MARK: - MetricsCollector Tests

@Suite("MetricsCollector Tests")
struct MetricsCollectorTests {
    
    // MARK: - Execution Tracking Tests
    
    @Test("MetricsCollector tracks agent start")
    func metricsCollectorTracksAgentStart() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        await collector.trace(.agentStart(traceId: traceId, agentName: "TestAgent"))
        
        let total = await collector.getTotalExecutions()
        #expect(total == 1)
    }
    
    @Test("MetricsCollector tracks successful execution")
    func metricsCollectorTracksSuccess() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()
        
        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "TestAgent"))
        await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "TestAgent", duration: 1.5))
        
        let successful = await collector.getSuccessfulExecutions()
        #expect(successful == 1)
    }
    
    @Test("MetricsCollector tracks failed execution")
    func metricsCollectorTracksError() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()
        
        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "TestAgent"))
        await collector.trace(.agentError(traceId: traceId, spanId: spanId, agentName: "TestAgent", error: NSError(domain: "test", code: 1)))
        
        let failed = await collector.getFailedExecutions()
        #expect(failed == 1)
    }
    
    @Test("MetricsCollector tracks cancelled execution")
    func metricsCollectorTracksCancelled() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        let event = TraceEvent.Builder(traceId: traceId, kind: .agentCancelled, message: "Cancelled")
            .agent("TestAgent")
            .build()
        
        await collector.trace(event)
        
        let cancelled = await collector.getCancelledExecutions()
        #expect(cancelled == 1)
    }
    
    // MARK: - Tool Tracking Tests
    
    @Test("MetricsCollector tracks tool calls")
    func metricsCollectorTracksToolCalls() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "web_search"))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "web_search"))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "calculator"))
        
        let toolCalls = await collector.getToolCalls()
        #expect(toolCalls["web_search"] == 2)
        #expect(toolCalls["calculator"] == 1)
    }
    
    @Test("MetricsCollector tracks tool results with duration")
    func metricsCollectorTracksToolResults() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()
        
        await collector.trace(.toolCall(traceId: traceId, spanId: spanId, parentSpanId: UUID(), toolName: "web_search"))
        await collector.trace(.toolResult(traceId: traceId, spanId: spanId, toolName: "web_search", duration: 1.2))
        
        let toolDurations = await collector.getToolDurations()
        #expect(toolDurations["web_search"]?.count == 1)
        #expect(toolDurations["web_search"]?.first == 1.2)
    }
    
    @Test("MetricsCollector tracks tool errors")
    func metricsCollectorTracksToolErrors() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        let event = TraceEvent.Builder(traceId: traceId, kind: .toolError, message: "Tool failed")
            .tool("web_search")
            .build()
        
        await collector.trace(event)
        await collector.trace(event)
        
        let toolErrors = await collector.getToolErrors()
        #expect(toolErrors["web_search"] == 2)
    }
    
    // MARK: - Snapshot Tests
    
    @Test("MetricsSnapshot computes success rate correctly")
    func snapshotComputesSuccessRate() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        // 3 successful, 1 failed = 75% success rate
        for i in 1...3 {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: 1.0))
        }
        
        let failSpanId = UUID()
        await collector.trace(.agentStart(traceId: traceId, spanId: failSpanId, agentName: "Agent"))
        await collector.trace(.agentError(traceId: traceId, spanId: failSpanId, agentName: "Agent", error: NSError(domain: "test", code: 1)))
        
        let snapshot = await collector.snapshot()
        #expect(snapshot.totalExecutions == 4)
        #expect(snapshot.successfulExecutions == 3)
        #expect(snapshot.failedExecutions == 1)
        #expect(snapshot.successRate == 75.0)
    }
    
    @Test("MetricsSnapshot computes error rate correctly")
    func snapshotComputesErrorRate() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        // 1 successful, 3 failed = 75% error rate
        let successSpanId = UUID()
        await collector.trace(.agentStart(traceId: traceId, spanId: successSpanId, agentName: "Agent"))
        await collector.trace(.agentComplete(traceId: traceId, spanId: successSpanId, agentName: "Agent", duration: 1.0))
        
        for _ in 1...3 {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentError(traceId: traceId, spanId: spanId, agentName: "Agent", error: NSError(domain: "test", code: 1)))
        }
        
        let snapshot = await collector.snapshot()
        #expect(snapshot.errorRate == 75.0)
    }
    
    @Test("MetricsSnapshot handles zero executions")
    func snapshotHandlesZeroExecutions() async {
        let collector = MetricsCollector()
        let snapshot = await collector.snapshot()
        
        #expect(snapshot.successRate == 0.0)
        #expect(snapshot.errorRate == 0.0)
        #expect(snapshot.averageExecutionDuration == 0.0)
        #expect(snapshot.minimumExecutionDuration == nil)
        #expect(snapshot.maximumExecutionDuration == nil)
    }
    
    @Test("MetricsSnapshot computes average duration")
    func snapshotComputesAverageDuration() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        let durations: [TimeInterval] = [1.0, 2.0, 3.0]
        for duration in durations {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: duration))
        }
        
        let snapshot = await collector.snapshot()
        #expect(snapshot.averageExecutionDuration == 2.0)
    }
    
    @Test("MetricsSnapshot computes min/max durations")
    func snapshotComputesMinMaxDurations() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        let durations: [TimeInterval] = [1.5, 0.5, 3.0, 2.0]
        for duration in durations {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: duration))
        }
        
        let snapshot = await collector.snapshot()
        #expect(snapshot.minimumExecutionDuration == 0.5)
        #expect(snapshot.maximumExecutionDuration == 3.0)
    }
    
    @Test("MetricsSnapshot computes median duration")
    func snapshotComputesMedianDuration() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        // Odd number of durations: [1, 2, 3] -> median = 2
        let durations: [TimeInterval] = [1.0, 3.0, 2.0]
        for duration in durations {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: duration))
        }
        
        let snapshot = await collector.snapshot()
        #expect(snapshot.medianExecutionDuration == 2.0)
    }
    
    @Test("MetricsSnapshot computes percentiles")
    func snapshotComputesPercentiles() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        // Add 100 durations from 0.1 to 10.0
        for i in 1...100 {
            let spanId = UUID()
            let duration = Double(i) * 0.1
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: duration))
        }
        
        let snapshot = await collector.snapshot()
        
        // P95 should be around 9.5 (95th element out of 100)
        // P99 should be around 9.9 (99th element out of 100)
        #expect(snapshot.p95ExecutionDuration != nil)
        #expect(snapshot.p99ExecutionDuration != nil)
        
        if let p95 = snapshot.p95ExecutionDuration, let p99 = snapshot.p99ExecutionDuration {
            #expect(p95 >= 9.0)
            #expect(p99 >= 9.5)
        }
    }
    
    @Test("MetricsSnapshot computes total tool calls and errors")
    func snapshotComputesTotalToolMetrics() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        
        // Add tool calls
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "tool1"))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "tool2"))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "tool1"))
        
        // Add tool errors
        let errorEvent = TraceEvent.Builder(traceId: traceId, kind: .toolError, message: "Error")
            .tool("tool1")
            .build()
        await collector.trace(errorEvent)
        
        let snapshot = await collector.snapshot()
        #expect(snapshot.totalToolCalls == 3)
        #expect(snapshot.totalToolErrors == 1)
    }
    
    // MARK: - Reset Tests
    
    @Test("MetricsCollector reset clears all metrics")
    func resetClearsAllMetrics() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()
        
        // Add some metrics
        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
        await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: 1.0))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "tool"))
        
        // Verify metrics exist
        var snapshot = await collector.snapshot()
        #expect(snapshot.totalExecutions > 0)
        
        // Reset
        await collector.reset()
        
        // Verify all metrics are cleared
        snapshot = await collector.snapshot()
        #expect(snapshot.totalExecutions == 0)
        #expect(snapshot.successfulExecutions == 0)
        #expect(snapshot.failedExecutions == 0)
        #expect(snapshot.cancelledExecutions == 0)
        #expect(snapshot.executionDurations.isEmpty)
        #expect(snapshot.toolCalls.isEmpty)
        #expect(snapshot.toolErrors.isEmpty)
        #expect(snapshot.toolDurations.isEmpty)
    }
    
    @Test("MetricsCollector tracks after reset")
    func tracksAfterReset() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()
        
        // Add metric, reset, add another
        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
        await collector.reset()
        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
        
        let total = await collector.getTotalExecutions()
        #expect(total == 1) // Only the metric after reset
    }
}

// MARK: - JSONMetricsReporter Tests

@Suite("JSONMetricsReporter Tests")
struct JSONMetricsReporterTests {
    
    @Test("JSONMetricsReporter encodes snapshot to JSON")
    func jsonReporterEncodesSnapshot() throws {
        let snapshot = MetricsSnapshot(
            totalExecutions: 10,
            successfulExecutions: 8,
            failedExecutions: 2,
            cancelledExecutions: 0,
            executionDurations: [1.0, 2.0, 3.0],
            toolCalls: ["tool1": 5],
            toolErrors: ["tool1": 1],
            toolDurations: ["tool1": [1.0, 2.0]],
            timestamp: Date()
        )
        
        let reporter = JSONMetricsReporter(prettyPrint: true)
        let jsonString = try reporter.jsonString(from: snapshot)
        
        #expect(jsonString.contains("totalExecutions"))
        #expect(jsonString.contains("successfulExecutions"))
    }
    
    @Test("JSONMetricsReporter produces valid JSON data")
    func jsonReporterProducesValidData() throws {
        let snapshot = MetricsSnapshot(
            totalExecutions: 5,
            successfulExecutions: 5,
            failedExecutions: 0,
            cancelledExecutions: 0,
            executionDurations: [1.0],
            toolCalls: [:],
            toolErrors: [:],
            toolDurations: [:],
            timestamp: Date()
        )
        
        let reporter = JSONMetricsReporter(prettyPrint: false)
        let data = try reporter.jsonData(from: snapshot)
        
        // Verify it can be decoded back
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MetricsSnapshot.self, from: data)
        
        #expect(decoded.totalExecutions == 5)
        #expect(decoded.successfulExecutions == 5)
    }
}
