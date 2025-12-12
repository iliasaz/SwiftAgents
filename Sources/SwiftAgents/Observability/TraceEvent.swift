// TraceEvent.swift
// SwiftAgents Framework
//
// Detailed trace events for agent execution monitoring.
// Provides comprehensive event tracking with metadata, spans, and source location.

import Foundation

// MARK: - Event Level

/// The severity level of a trace event.
public enum EventLevel: Int, Sendable, Codable, Comparable, CaseIterable {
    case trace = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5

    public static func < (lhs: EventLevel, rhs: EventLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Event Kind

/// The kind of event being traced.
public enum EventKind: String, Sendable, Codable, CaseIterable {
    /// Agent execution started
    case agentStart
    /// Agent execution completed successfully
    case agentComplete
    /// Agent execution encountered an error
    case agentError
    /// Agent execution was cancelled
    case agentCancelled

    /// Tool invocation started
    case toolCall
    /// Tool returned a result
    case toolResult
    /// Tool execution failed
    case toolError

    /// Agent reasoning/thinking step
    case thought
    /// Agent made a decision
    case decision
    /// Agent created or updated a plan
    case plan

    /// Memory read operation
    case memoryRead
    /// Memory write operation
    case memoryWrite

    /// Execution checkpoint
    case checkpoint
    /// Performance or custom metric
    case metric
    /// Custom event type
    case custom
}

// MARK: - Source Location

/// Source code location information for debugging.
public struct SourceLocation: Sendable, Codable, Equatable, Hashable {
    public let file: String
    public let function: String
    public let line: Int

    /// Creates a source location with the provided information.
    public init(
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.file = file
        self.function = function
        self.line = line
    }

    /// Returns just the filename without the full path.
    public var filename: String {
        (file as NSString).lastPathComponent
    }

    /// Returns a formatted string representation.
    public var formatted: String {
        "\(filename):\(line) - \(function)"
    }
}

// MARK: - Error Info

/// Detailed error information for trace events.
public struct ErrorInfo: Sendable, Codable, Equatable, Hashable {
    public let type: String
    public let message: String
    public let stackTrace: [String]?
    public let underlyingError: String?

    /// Creates error information from an error instance.
    public init(
        type: String,
        message: String,
        stackTrace: [String]? = nil,
        underlyingError: String? = nil
    ) {
        self.type = type
        self.message = message
        self.stackTrace = stackTrace
        self.underlyingError = underlyingError
    }

    /// Creates error information from a Swift Error.
    public init(from error: Error) {
        self.type = String(reflecting: Swift.type(of: error))
        self.message = error.localizedDescription
        self.stackTrace = nil

        // Attempt to extract underlying error
        if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
            self.underlyingError = String(describing: underlyingError)
        } else {
            self.underlyingError = nil
        }
    }
}

// MARK: - Trace Event

/// A detailed trace event for agent execution monitoring.
public struct TraceEvent: Sendable, Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier for this event
    public let id: UUID

    /// Trace ID - groups related events across an entire operation
    public let traceId: UUID

    /// Span ID - identifies this specific event/operation
    public let spanId: UUID

    /// Parent span ID - links to the parent operation
    public let parentSpanId: UUID?

    /// Timestamp when the event occurred
    public let timestamp: Date

    /// Duration of the operation (nil for instantaneous events)
    public let duration: TimeInterval?

    /// The kind of event
    public let kind: EventKind

    /// The severity level
    public let level: EventLevel

    /// Human-readable message
    public let message: String

    /// Additional metadata
    public let metadata: [String: SendableValue]

    /// Name of the agent that generated this event
    public let agentName: String?

    /// Name of the tool being executed (for tool events)
    public let toolName: String?

    /// Error information (for error events)
    public let error: ErrorInfo?

    /// Source code location
    public let source: SourceLocation?

    /// Creates a new trace event.
    public init(
        id: UUID = UUID(),
        traceId: UUID,
        spanId: UUID = UUID(),
        parentSpanId: UUID? = nil,
        timestamp: Date = Date(),
        duration: TimeInterval? = nil,
        kind: EventKind,
        level: EventLevel = .info,
        message: String,
        metadata: [String: SendableValue] = [:],
        agentName: String? = nil,
        toolName: String? = nil,
        error: ErrorInfo? = nil,
        source: SourceLocation? = nil
    ) {
        self.id = id
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.timestamp = timestamp
        self.duration = duration
        self.kind = kind
        self.level = level
        self.message = message
        self.metadata = metadata
        self.agentName = agentName
        self.toolName = toolName
        self.error = error
        self.source = source
    }
}

// MARK: - Trace Event Builder

extension TraceEvent {
    /// Fluent builder for creating trace events.
    public final class Builder: @unchecked Sendable {
        private let id: UUID
        private let traceId: UUID
        private let spanId: UUID
        private var parentSpanId: UUID?
        private var timestamp: Date
        private var duration: TimeInterval?
        private var kind: EventKind
        private var level: EventLevel
        private var message: String
        private var metadata: [String: SendableValue]
        private var agentName: String?
        private var toolName: String?
        private var error: ErrorInfo?
        private var source: SourceLocation?

        /// Creates a new builder with required parameters.
        public init(
            traceId: UUID,
            kind: EventKind,
            message: String,
            id: UUID = UUID(),
            spanId: UUID = UUID(),
            timestamp: Date = Date(),
            level: EventLevel = .info
        ) {
            self.id = id
            self.traceId = traceId
            self.spanId = spanId
            self.timestamp = timestamp
            self.kind = kind
            self.level = level
            self.message = message
            self.metadata = [:]
        }

        /// Sets the parent span ID.
        @discardableResult
        public func parentSpan(_ id: UUID) -> Builder {
            self.parentSpanId = id
            return self
        }

        /// Sets the timestamp.
        @discardableResult
        public func timestamp(_ date: Date) -> Builder {
            self.timestamp = date
            return self
        }

        /// Sets the duration.
        @discardableResult
        public func duration(_ duration: TimeInterval) -> Builder {
            self.duration = duration
            return self
        }

        /// Sets the event level.
        @discardableResult
        public func level(_ level: EventLevel) -> Builder {
            self.level = level
            return self
        }

        /// Sets the message.
        @discardableResult
        public func message(_ message: String) -> Builder {
            self.message = message
            return self
        }

        /// Adds a metadata key-value pair.
        @discardableResult
        public func metadata(key: String, value: SendableValue) -> Builder {
            self.metadata[key] = value
            return self
        }

        /// Replaces all metadata.
        @discardableResult
        public func metadata(_ metadata: [String: SendableValue]) -> Builder {
            self.metadata = metadata
            return self
        }

        /// Adds multiple metadata entries.
        @discardableResult
        public func addingMetadata(_ additional: [String: SendableValue]) -> Builder {
            self.metadata.merge(additional) { _, new in new }
            return self
        }

        /// Sets the agent name.
        @discardableResult
        public func agent(_ name: String) -> Builder {
            self.agentName = name
            return self
        }

        /// Sets the tool name.
        @discardableResult
        public func tool(_ name: String) -> Builder {
            self.toolName = name
            return self
        }

        /// Sets error information from an Error.
        @discardableResult
        public func error(_ error: Error) -> Builder {
            self.error = ErrorInfo(from: error)
            return self
        }

        /// Sets error information directly.
        @discardableResult
        public func error(_ errorInfo: ErrorInfo) -> Builder {
            self.error = errorInfo
            return self
        }

        /// Sets the source location.
        @discardableResult
        public func source(
            file: String = #file,
            function: String = #function,
            line: Int = #line
        ) -> Builder {
            self.source = SourceLocation(file: file, function: function, line: line)
            return self
        }

        /// Sets the source location directly.
        @discardableResult
        public func source(_ location: SourceLocation) -> Builder {
            self.source = location
            return self
        }

        /// Builds the trace event.
        public func build() -> TraceEvent {
            TraceEvent(
                id: id,
                traceId: traceId,
                spanId: spanId,
                parentSpanId: parentSpanId,
                timestamp: timestamp,
                duration: duration,
                kind: kind,
                level: level,
                message: message,
                metadata: metadata,
                agentName: agentName,
                toolName: toolName,
                error: error,
                source: source
            )
        }
    }
}

// MARK: - Convenience Constructors

extension TraceEvent {
    /// Creates an agent start event.
    public static func agentStart(
        traceId: UUID,
        spanId: UUID = UUID(),
        agentName: String,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .agentStart, message: "Agent started", spanId: spanId)
            .agent(agentName)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates an agent complete event.
    public static func agentComplete(
        traceId: UUID,
        spanId: UUID,
        agentName: String,
        duration: TimeInterval,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .agentComplete, message: "Agent completed", spanId: spanId)
            .agent(agentName)
            .duration(duration)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates an agent error event.
    public static func agentError(
        traceId: UUID,
        spanId: UUID,
        agentName: String,
        error: Error,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .agentError, message: "Agent error", spanId: spanId, level: .error)
            .agent(agentName)
            .error(error)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates a tool call event.
    public static func toolCall(
        traceId: UUID,
        spanId: UUID = UUID(),
        parentSpanId: UUID?,
        toolName: String,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .toolCall, message: "Tool call", spanId: spanId, level: .debug)
            .parentSpan(parentSpanId ?? UUID())
            .tool(toolName)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates a tool result event.
    public static func toolResult(
        traceId: UUID,
        spanId: UUID,
        toolName: String,
        duration: TimeInterval,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .toolResult, message: "Tool result", spanId: spanId, level: .debug)
            .tool(toolName)
            .duration(duration)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates a thought event.
    public static func thought(
        traceId: UUID,
        spanId: UUID,
        agentName: String,
        thought: String,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        var meta = metadata
        meta["thought"] = .string(thought)

        return Builder(traceId: traceId, kind: .thought, message: thought, spanId: spanId, level: .trace)
            .agent(agentName)
            .metadata(meta)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates a custom event.
    public static func custom(
        traceId: UUID,
        spanId: UUID = UUID(),
        message: String,
        level: EventLevel = .info,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .custom, message: message, spanId: spanId, level: level)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }
}

// MARK: - CustomStringConvertible

extension TraceEvent: CustomStringConvertible {
    public var description: String {
        var parts = [
            "[\(level)]",
            kind.rawValue,
        ]

        if let agentName {
            parts.append("agent=\(agentName)")
        }

        if let toolName {
            parts.append("tool=\(toolName)")
        }

        parts.append(message)

        if let duration {
            parts.append("(\(String(format: "%.2f", duration * 1000))ms)")
        }

        return parts.joined(separator: " ")
    }
}

extension EventLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
}
