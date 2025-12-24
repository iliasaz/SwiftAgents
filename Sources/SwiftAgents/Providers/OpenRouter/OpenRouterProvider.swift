// OpenRouterProvider.swift
// SwiftAgents Framework
//
// OpenRouter inference provider for accessing multiple LLM backends.

import Foundation

// MARK: - OpenRouterProvider

/// OpenRouter inference provider for accessing multiple LLM backends.
///
/// OpenRouter provides unified access to models from OpenAI, Anthropic, Google,
/// Meta, Mistral, and other providers through a single API.
///
/// Example:
/// ```swift
/// let provider = OpenRouterProvider(
///     apiKey: "sk-or-v1-...",
///     model: .claude35Sonnet
/// )
///
/// let response = try await provider.generate(
///     prompt: "Explain quantum computing",
///     options: .default
/// )
/// ```
public actor OpenRouterProvider: InferenceProvider {
    // MARK: - Properties

    private let configuration: OpenRouterConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var rateLimitInfo: RateLimitInfo?

    /// Cached model description for nonisolated access.
    private let modelDescription: String

    // MARK: - Initialization

    /// Creates an OpenRouter provider with the given configuration.
    /// - Parameter configuration: The provider configuration.
    public init(configuration: OpenRouterConfiguration) {
        self.configuration = configuration
        self.modelDescription = configuration.model.identifier

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout.timeInterval
        sessionConfig.timeoutIntervalForResource = configuration.timeout.timeInterval * 2
        self.session = URLSession(configuration: sessionConfig)

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// Creates an OpenRouter provider with an API key and model.
    /// - Parameters:
    ///   - apiKey: The OpenRouter API key.
    ///   - model: The model to use. Default: .gpt4o
    public init(apiKey: String, model: OpenRouterModel = .gpt4o) {
        self.init(configuration: OpenRouterConfiguration(apiKey: apiKey, model: model))
    }

    // MARK: - InferenceProvider Conformance

    /// Generates a response for the given prompt.
    /// - Parameters:
    ///   - prompt: The input prompt.
    ///   - options: Generation options.
    /// - Returns: The generated text.
    /// - Throws: `AgentError` if generation fails.
    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidInput(reason: "Prompt cannot be empty")
        }

        let request = try buildRequest(prompt: prompt, options: options, stream: false)
        let maxRetries = configuration.retryStrategy.maxRetries

        for attempt in 0..<(maxRetries + 1) {
            try Task.checkCancellation()

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AgentError.generationFailed(reason: "Invalid response type")
                }

                // Update rate limit info
                rateLimitInfo = RateLimitInfo(headers: httpResponse.allHeaderFields)

                // Handle HTTP errors
                if httpResponse.statusCode != 200 {
                    try handleHTTPError(statusCode: httpResponse.statusCode, data: data, attempt: attempt, maxRetries: maxRetries)
                    continue
                }

                // Parse response
                let chatResponse = try decoder.decode(ChatCompletionResponse.self, from: data)

                guard let content = chatResponse.choices.first?.message.content else {
                    throw AgentError.generationFailed(reason: "No content in response")
                }

                return content

            } catch let error as AgentError {
                if attempt == maxRetries {
                    throw error
                }
                // Retry on retryable errors
                if case .rateLimitExceeded = error {
                    try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
                    continue
                }
                throw error
            } catch is CancellationError {
                throw AgentError.cancelled
            } catch {
                if attempt == maxRetries {
                    throw AgentError.generationFailed(reason: error.localizedDescription)
                }
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
            }
        }

        throw AgentError.generationFailed(reason: "Max retries exceeded")
    }

    /// Streams a response for the given prompt.
    /// - Parameters:
    ///   - prompt: The input prompt.
    ///   - options: Generation options.
    /// - Returns: An async stream of response tokens.
    public nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.performStream(prompt: prompt, options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Generates a response with potential tool calls.
    /// - Parameters:
    ///   - prompt: The input prompt.
    ///   - tools: Available tool definitions.
    ///   - options: Generation options.
    /// - Returns: The inference response which may include tool calls.
    /// - Throws: `AgentError` if generation fails.
    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolDefinition],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidInput(reason: "Prompt cannot be empty")
        }

        let request = try buildRequest(prompt: prompt, options: options, stream: false, tools: tools)
        let maxRetries = configuration.retryStrategy.maxRetries

        for attempt in 0..<(maxRetries + 1) {
            try Task.checkCancellation()

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AgentError.generationFailed(reason: "Invalid response type")
                }

                // Update rate limit info
                rateLimitInfo = RateLimitInfo(headers: httpResponse.allHeaderFields)

                // Handle HTTP errors
                if httpResponse.statusCode != 200 {
                    try handleHTTPError(statusCode: httpResponse.statusCode, data: data, attempt: attempt, maxRetries: maxRetries)
                    continue
                }

                // Parse response
                let chatResponse = try decoder.decode(ChatCompletionResponse.self, from: data)

                guard let choice = chatResponse.choices.first else {
                    throw AgentError.generationFailed(reason: "No choices in response")
                }

                // Map finish reason
                let finishReason = mapFinishReason(choice.finishReason)

                // Parse tool calls if present
                var parsedToolCalls: [InferenceResponse.ParsedToolCall] = []
                if let toolCalls = choice.message.toolCalls {
                    for toolCall in toolCalls {
                        let arguments = try parseToolArguments(toolCall.function.arguments)
                        parsedToolCalls.append(InferenceResponse.ParsedToolCall(
                            id: toolCall.id,
                            name: toolCall.function.name,
                            arguments: arguments
                        ))
                    }
                }

                // Parse usage statistics
                var usage: InferenceResponse.TokenUsage?
                if let responseUsage = chatResponse.usage {
                    usage = InferenceResponse.TokenUsage(
                        inputTokens: responseUsage.promptTokens,
                        outputTokens: responseUsage.completionTokens
                    )
                }

                return InferenceResponse(
                    content: choice.message.content,
                    toolCalls: parsedToolCalls,
                    finishReason: finishReason,
                    usage: usage
                )

            } catch let error as AgentError {
                if attempt == maxRetries {
                    throw error
                }
                if case .rateLimitExceeded = error {
                    try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
                    continue
                }
                throw error
            } catch is CancellationError {
                throw AgentError.cancelled
            } catch {
                if attempt == maxRetries {
                    throw AgentError.generationFailed(reason: error.localizedDescription)
                }
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
            }
        }

        throw AgentError.generationFailed(reason: "Max retries exceeded")
    }

    // MARK: - Private Methods

    private func performStream(
        prompt: String,
        options: InferenceOptions,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidInput(reason: "Prompt cannot be empty")
        }

        let request = try buildRequest(prompt: prompt, options: options, stream: true)
        let maxRetries = configuration.retryStrategy.maxRetries

        for attempt in 0..<(maxRetries + 1) {
            try Task.checkCancellation()

            do {
                let (bytes, response) = try await session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AgentError.generationFailed(reason: "Invalid response type")
                }

                // Update rate limit info
                rateLimitInfo = RateLimitInfo(headers: httpResponse.allHeaderFields)

                // Handle HTTP errors by collecting error data
                if httpResponse.statusCode != 200 {
                    var errorData = Data()
                    for try await byte in bytes {
                        errorData.append(byte)
                        if errorData.count >= 10000 { break }
                    }
                    try handleHTTPError(statusCode: httpResponse.statusCode, data: errorData, attempt: attempt, maxRetries: maxRetries)
                    continue
                }

                // Process SSE stream
                for try await line in bytes.lines {
                    try Task.checkCancellation()

                    guard line.hasPrefix("data: ") else { continue }
                    let jsonString = String(line.dropFirst(6))

                    if jsonString == "[DONE]" {
                        continuation.finish()
                        return
                    }

                    guard let jsonData = jsonString.data(using: .utf8) else { continue }

                    do {
                        let chunk = try decoder.decode(StreamChunk.self, from: jsonData)
                        if let content = chunk.choices.first?.delta.content {
                            continuation.yield(content)
                        }
                    } catch {
                        // Skip malformed chunks
                        continue
                    }
                }

                continuation.finish()
                return

            } catch let error as AgentError {
                if attempt == maxRetries {
                    throw error
                }
                if case .rateLimitExceeded = error {
                    try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
                    continue
                }
                throw error
            } catch is CancellationError {
                throw AgentError.cancelled
            } catch {
                if attempt == maxRetries {
                    throw AgentError.generationFailed(reason: error.localizedDescription)
                }
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
            }
        }

        throw AgentError.generationFailed(reason: "Max retries exceeded")
    }

    private func buildRequest(
        prompt: String,
        options: InferenceOptions,
        stream: Bool,
        tools: [ToolDefinition]? = nil
    ) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        // OpenRouter-specific headers
        if let siteURL = configuration.siteURL {
            request.setValue(siteURL.absoluteString, forHTTPHeaderField: "HTTP-Referer")
        }
        if let appName = configuration.appName {
            request.setValue(appName, forHTTPHeaderField: "X-Title")
        }

        var body: [String: Any] = [
            "model": configuration.model.identifier,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "stream": stream,
            "temperature": options.temperature
        ]

        if let maxTokens = options.maxTokens {
            body["max_tokens"] = maxTokens
        }

        if !options.stopSequences.isEmpty {
            body["stop"] = options.stopSequences
        }

        if let topP = options.topP {
            body["top_p"] = topP
        }

        if let presencePenalty = options.presencePenalty {
            body["presence_penalty"] = presencePenalty
        }

        if let frequencyPenalty = options.frequencyPenalty {
            body["frequency_penalty"] = frequencyPenalty
        }

        // Add tools if provided
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { convertToolDefinition($0) }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func convertToolDefinition(_ tool: ToolDefinition) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for param in tool.parameters {
            properties[param.name] = [
                "type": convertParameterType(param.type),
                "description": param.description
            ]
            if param.isRequired {
                required.append(param.name)
            }
        }

        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required
                ]
            ]
        ]
    }

    private func convertParameterType(_ type: ToolParameter.ParameterType) -> String {
        switch type {
        case .string: "string"
        case .int: "integer"
        case .double: "number"
        case .bool: "boolean"
        case .array: "array"
        case .object: "object"
        case .oneOf: "string"
        case .any: "string"
        }
    }

    private func handleHTTPError(statusCode: Int, data: Data, attempt: Int, maxRetries: Int) throws {
        let errorMessage: String
        if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
            errorMessage = errorResponse.error.message
        } else if let rawMessage = String(data: data, encoding: .utf8) {
            errorMessage = rawMessage
        } else {
            errorMessage = "Unknown error"
        }

        switch statusCode {
        case 401:
            throw AgentError.inferenceProviderUnavailable(reason: "Invalid API key")
        case 429:
            let retryAfter: TimeInterval? = pow(2.0, Double(attempt + 1))
            throw AgentError.rateLimitExceeded(retryAfter: retryAfter)
        case 400:
            throw AgentError.invalidInput(reason: errorMessage)
        case 404:
            throw AgentError.modelNotAvailable(model: configuration.model.identifier)
        case 500, 502, 503:
            if attempt < maxRetries {
                return // Will retry
            }
            throw AgentError.inferenceProviderUnavailable(reason: "Server error: \(errorMessage)")
        default:
            throw AgentError.generationFailed(reason: "HTTP \(statusCode): \(errorMessage)")
        }
    }

    private func mapFinishReason(_ reason: String?) -> InferenceResponse.FinishReason {
        switch reason {
        case "tool_calls": .toolCall
        case "length": .maxTokens
        case "content_filter": .contentFilter
        case "stop", nil: .completed
        default: .completed
        }
    }

    private func parseToolArguments(_ argumentsString: String) throws -> [String: SendableValue] {
        guard let data = argumentsString.data(using: .utf8) else {
            throw AgentError.invalidToolArguments(toolName: "unknown", reason: "Invalid argument encoding")
        }

        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.invalidToolArguments(toolName: "unknown", reason: "Arguments must be an object")
        }

        return try convertToSendableValue(jsonObject)
    }

    private func convertToSendableValue(_ dict: [String: Any]) throws -> [String: SendableValue] {
        var result: [String: SendableValue] = [:]
        for (key, value) in dict {
            result[key] = try convertAnyToSendableValue(value)
        }
        return result
    }

    private func convertAnyToSendableValue(_ value: Any) throws -> SendableValue {
        switch value {
        case is NSNull:
            return .null
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            if double.truncatingRemainder(dividingBy: 1) == 0,
               double >= Double(Int.min), double <= Double(Int.max) {
                return .int(Int(double))
            }
            return .double(double)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(try array.map { try convertAnyToSendableValue($0) })
        case let dict as [String: Any]:
            return .dictionary(try convertToSendableValue(dict))
        default:
            throw AgentError.invalidToolArguments(toolName: "unknown", reason: "Unsupported type: \(type(of: value))")
        }
    }
}

// MARK: - CustomStringConvertible

extension OpenRouterProvider: CustomStringConvertible {
    public nonisolated var description: String {
        "OpenRouterProvider(model: \(modelDescription))"
    }
}

// MARK: - Rate Limit Info

/// Internal rate limit information from OpenRouter API responses.
private struct RateLimitInfo: Sendable {
    /// Requests remaining in the current window.
    let requestsRemaining: Int?

    /// Tokens remaining in the current window.
    let tokensRemaining: Int?

    /// When the rate limit window resets.
    let resetTime: Date?

    /// Creates rate limit info from response headers.
    /// - Parameter headers: HTTP response headers.
    init(headers: [AnyHashable: Any]) {
        if let remaining = headers["x-ratelimit-remaining-requests"] as? String {
            requestsRemaining = Int(remaining)
        } else {
            requestsRemaining = nil
        }

        if let tokens = headers["x-ratelimit-remaining-tokens"] as? String {
            tokensRemaining = Int(tokens)
        } else {
            tokensRemaining = nil
        }

        if let reset = headers["x-ratelimit-reset-requests"] as? String,
           let resetInterval = TimeInterval(reset) {
            resetTime = Date().addingTimeInterval(resetInterval)
        } else {
            resetTime = nil
        }
    }
}

// MARK: - Response Types

private struct ChatCompletionResponse: Decodable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let index: Int
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let role: String
        let content: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable {
        let id: String
        let type: String
        let function: FunctionCall
    }

    struct FunctionCall: Decodable {
        let name: String
        let arguments: String
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private struct StreamChunk: Decodable {
    let id: String?
    let choices: [StreamChoice]

    struct StreamChoice: Decodable {
        let index: Int
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let role: String?
        let content: String?
    }
}

private struct ErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
        let type: String?
        let code: String?
    }
}
