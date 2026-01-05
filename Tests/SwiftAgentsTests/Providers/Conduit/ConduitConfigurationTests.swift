// ConduitConfigurationTests.swift
// SwiftAgentsTests
//
// Comprehensive tests for ConduitConfiguration validation and factory methods.

import Conduit
import Foundation
@testable import SwiftAgents
import Testing

@Suite("ConduitConfiguration Tests")
struct ConduitConfigurationTests {
    // MARK: - Validation Tests (Validation happens in throwing init)

    @Test("valid Anthropic configuration passes validation")
    func validAnthropicConfigurationPassesValidation() throws {
        let config = try ConduitConfiguration.anthropic(
            apiKey: "test-api-key",
            model: .claudeSonnet45,
            systemPrompt: "You are helpful",
            timeout: 30,
            maxRetries: 3
        )

        #expect(config.providerType.displayName == "Anthropic")
        #expect(config.timeout == 30)
        #expect(config.maxRetries == 3)
    }

    @Test("empty API key throws emptyAPIKey")
    func emptyAPIKeyThrowsError() throws {
        #expect(throws: ConduitConfigurationError.emptyAPIKey) {
            _ = try ConduitConfiguration.anthropic(
                apiKey: "",
                model: .claudeSonnet45
            )
        }
    }

    @Test("whitespace-only API key throws emptyAPIKey")
    func whitespaceOnlyAPIKeyThrowsError() throws {
        #expect(throws: ConduitConfigurationError.emptyAPIKey) {
            _ = try ConduitConfiguration.anthropic(
                apiKey: "   ",
                model: .claudeSonnet45
            )
        }
    }

    @Test("negative timeout throws invalidTimeout")
    func negativeTimeoutThrowsError() throws {
        #expect(throws: ConduitConfigurationError.invalidTimeout(-1)) {
            _ = try ConduitConfiguration(
                providerType: .foundationModels,
                timeout: -1,
                maxRetries: 3
            )
        }
    }

    @Test("zero timeout throws invalidTimeout")
    func zeroTimeoutThrowsError() throws {
        #expect(throws: ConduitConfigurationError.invalidTimeout(0)) {
            _ = try ConduitConfiguration(
                providerType: .foundationModels,
                timeout: 0,
                maxRetries: 3
            )
        }
    }

    @Test("negative max retries throws invalidMaxRetries")
    func negativeMaxRetriesThrowsError() throws {
        #expect(throws: ConduitConfigurationError.invalidMaxRetries(-1)) {
            _ = try ConduitConfiguration(
                providerType: .foundationModels,
                timeout: 30,
                maxRetries: -1
            )
        }
    }

    @Test("temperature below 0 throws invalidTemperature")
    func temperatureBelowZeroThrowsError() throws {
        #expect(throws: ConduitConfigurationError.invalidTemperature(-0.1)) {
            _ = try ConduitConfiguration(
                providerType: .foundationModels,
                timeout: 30,
                maxRetries: 3,
                temperature: -0.1
            )
        }
    }

    @Test("temperature above 2 throws invalidTemperature")
    func temperatureAboveTwoThrowsError() throws {
        #expect(throws: ConduitConfigurationError.invalidTemperature(2.1)) {
            _ = try ConduitConfiguration(
                providerType: .foundationModels,
                timeout: 30,
                maxRetries: 3,
                temperature: 2.1
            )
        }
    }

    @Test("topP at 0 throws invalidTopP")
    func topPAtZeroThrowsError() throws {
        #expect(throws: ConduitConfigurationError.invalidTopP(0.0)) {
            _ = try ConduitConfiguration(
                providerType: .foundationModels,
                timeout: 30,
                maxRetries: 3,
                topP: 0.0
            )
        }
    }

    @Test("topP above 1 throws invalidTopP")
    func topPAboveOneThrowsError() throws {
        #expect(throws: ConduitConfigurationError.invalidTopP(1.1)) {
            _ = try ConduitConfiguration(
                providerType: .foundationModels,
                timeout: 30,
                maxRetries: 3,
                topP: 1.1
            )
        }
    }

    @Test("negative topK throws invalidTopK")
    func negativeTopKThrowsError() throws {
        #expect(throws: ConduitConfigurationError.invalidTopK(-1)) {
            _ = try ConduitConfiguration(
                providerType: .foundationModels,
                timeout: 30,
                maxRetries: 3,
                topK: -1
            )
        }
    }

    @Test("zero topK throws invalidTopK")
    func zeroTopKThrowsError() throws {
        #expect(throws: ConduitConfigurationError.invalidTopK(0)) {
            _ = try ConduitConfiguration(
                providerType: .foundationModels,
                timeout: 30,
                maxRetries: 3,
                topK: 0
            )
        }
    }

    // MARK: - Factory Method Tests

    @Test("anthropic factory creates valid configuration")
    func anthropicFactoryCreatesValidConfiguration() throws {
        let config = try ConduitConfiguration.anthropic(
            apiKey: "test-anthropic-key",
            model: .claudeSonnet45
        )

        #expect(config.providerType.displayName == "Anthropic")
        #expect(config.providerType.modelString.contains("claude-sonnet"))
    }

    @Test("openAI factory creates valid configuration")
    func openAIFactoryCreatesValidConfiguration() throws {
        let config = try ConduitConfiguration.openAI(
            apiKey: "test-openai-key",
            model: .gpt4o
        )

        #expect(config.providerType.displayName == "OpenAI")
        #expect(config.providerType.modelString == "gpt-4o")
    }

    @Test("mlx factory creates valid configuration")
    func mlxFactoryCreatesValidConfiguration() throws {
        let config = try ConduitConfiguration.mlx(
            model: .llama3_2_1b
        )

        #expect(config.providerType.displayName == "MLX (Local)")
        #expect(config.providerType.isOnDevice == true)
    }

    @Test("huggingFace factory creates valid configuration")
    func huggingFaceFactoryCreatesValidConfiguration() throws {
        let config = try ConduitConfiguration.huggingFace(
            token: "test-hf-token",
            model: .huggingFace("meta-llama/Llama-3.1-8B-Instruct")
        )

        #expect(config.providerType.displayName == "HuggingFace")
    }

    @Test("foundationModels factory creates valid configuration")
    func foundationModelsFactoryCreatesValidConfiguration() throws {
        let config = try ConduitConfiguration.foundationModels(
            systemPrompt: "You are helpful"
        )

        #expect(config.providerType.displayName == "Apple Foundation Models")
        #expect(config.providerType.isOnDevice == true)
        #expect(config.maxRetries == 0) // Foundation Models don't typically need retries
    }

    // MARK: - Retry Strategy Tests

    @Test("default retry strategy has sensible values")
    func defaultRetryStrategyHasSensibleValues() {
        let strategy = ConduitRetryStrategy.default

        #expect(strategy.maxRetries == 3)
        #expect(strategy.baseDelay == 1.0)
        #expect(strategy.maxDelay == 30.0)
        #expect(strategy.backoffMultiplier == 2.0)
    }

    @Test("none retry strategy has zero retries")
    func noneRetryStrategyHasZeroRetries() {
        let strategy = ConduitRetryStrategy.none

        #expect(strategy.maxRetries == 0)
    }

    @Test("aggressive retry strategy has high retry count")
    func aggressiveRetryStrategyHasHighRetryCount() {
        let strategy = ConduitRetryStrategy.aggressive

        #expect(strategy.maxRetries == 5)
        #expect(strategy.baseDelay == 0.5)
        #expect(strategy.maxDelay == 60.0)
    }

    @Test("custom retry strategy allows configuration")
    func customRetryStrategyAllowsConfiguration() {
        let strategy = ConduitRetryStrategy(
            maxRetries: 10,
            baseDelay: 2.0,
            maxDelay: 120.0,
            backoffMultiplier: 3.0
        )

        #expect(strategy.maxRetries == 10)
        #expect(strategy.baseDelay == 2.0)
        #expect(strategy.maxDelay == 120.0)
        #expect(strategy.backoffMultiplier == 3.0)
    }

    @Test("retry strategy calculates delay correctly")
    func retryStrategyCalculatesDelayCorrectly() {
        let strategy = ConduitRetryStrategy(
            maxRetries: 5,
            baseDelay: 1.0,
            maxDelay: 30.0,
            backoffMultiplier: 2.0
        )

        #expect(strategy.delay(forAttempt: 1) == 1.0)
        #expect(strategy.delay(forAttempt: 2) == 2.0)
        #expect(strategy.delay(forAttempt: 3) == 4.0)
        #expect(strategy.delay(forAttempt: 4) == 8.0)
        #expect(strategy.delay(forAttempt: 5) == 16.0)
    }

    @Test("retry strategy respects max delay")
    func retryStrategyRespectsMaxDelay() {
        let strategy = ConduitRetryStrategy(
            maxRetries: 10,
            baseDelay: 1.0,
            maxDelay: 10.0,
            backoffMultiplier: 2.0
        )

        // At attempt 5: 1 * 2^4 = 16, but max is 10
        #expect(strategy.delay(forAttempt: 5) == 10.0)
        #expect(strategy.delay(forAttempt: 10) == 10.0)
    }

    // MARK: - Equatable Tests

    @Test("identical configurations are equal")
    func identicalConfigurationsAreEqual() throws {
        let config1 = try ConduitConfiguration(
            providerType: .foundationModels,
            systemPrompt: "Test",
            timeout: 30,
            maxRetries: 3,
            temperature: 0.7
        )

        let config2 = try ConduitConfiguration(
            providerType: .foundationModels,
            systemPrompt: "Test",
            timeout: 30,
            maxRetries: 3,
            temperature: 0.7
        )

        #expect(config1 == config2)
    }

    @Test("different provider types make configurations not equal")
    func differentProviderTypesMakeConfigurationsNotEqual() throws {
        let config1 = try ConduitConfiguration.foundationModels()
        let config2 = try ConduitConfiguration.mlx(model: .llama3_2_1b)

        #expect(config1 != config2)
    }

    @Test("different temperatures make configurations not equal")
    func differentTemperaturesMakeConfigurationsNotEqual() throws {
        let config1 = try ConduitConfiguration(
            providerType: .foundationModels,
            timeout: 30,
            maxRetries: 3,
            temperature: 0.7
        )
        let config2 = try ConduitConfiguration(
            providerType: .foundationModels,
            timeout: 30,
            maxRetries: 3,
            temperature: 0.8
        )

        #expect(config1 != config2)
    }

    // MARK: - Edge Cases

    @Test("maximum valid temperature is accepted")
    func maximumValidTemperatureIsAccepted() throws {
        let config = try ConduitConfiguration(
            providerType: .foundationModels,
            timeout: 30,
            maxRetries: 3,
            temperature: 2.0
        )

        #expect(config.temperature == 2.0)
    }

    @Test("minimum valid temperature is accepted")
    func minimumValidTemperatureIsAccepted() throws {
        let config = try ConduitConfiguration(
            providerType: .foundationModels,
            timeout: 30,
            maxRetries: 3,
            temperature: 0.0
        )

        #expect(config.temperature == 0.0)
    }

    @Test("nil optional parameters are accepted")
    func nilOptionalParametersAreAccepted() throws {
        let config = try ConduitConfiguration(
            providerType: .foundationModels,
            timeout: 30,
            maxRetries: 3,
            temperature: nil,
            topP: nil,
            topK: nil,
            maxTokens: nil
        )

        #expect(config.temperature == nil)
        #expect(config.topP == nil)
        #expect(config.topK == nil)
        #expect(config.maxTokens == nil)
    }

    @Test("system prompt is preserved")
    func systemPromptIsPreserved() throws {
        let systemPrompt = "You are a helpful assistant specialized in Swift programming."
        let config = try ConduitConfiguration.foundationModels(
            systemPrompt: systemPrompt
        )

        #expect(config.systemPrompt == systemPrompt)
    }

    // MARK: - Provider Type Properties

    @Test("cloud providers require network")
    func cloudProvidersRequireNetwork() throws {
        let anthropicConfig = try ConduitConfiguration.anthropic(
            apiKey: "test-key",
            model: .claudeSonnet45
        )
        let openAIConfig = try ConduitConfiguration.openAI(
            apiKey: "test-key",
            model: .gpt4o
        )

        #expect(anthropicConfig.providerType.requiresNetwork == true)
        #expect(openAIConfig.providerType.requiresNetwork == true)
    }

    @Test("local providers do not require network")
    func localProvidersDoNotRequireNetwork() throws {
        let mlxConfig = try ConduitConfiguration.mlx(model: .llama3_2_1b)
        let fmConfig = try ConduitConfiguration.foundationModels()

        #expect(mlxConfig.providerType.requiresNetwork == false)
        #expect(fmConfig.providerType.requiresNetwork == false)
    }

    // MARK: - Description Tests

    @Test("configuration has meaningful description")
    func configurationHasMeaningfulDescription() throws {
        let config = try ConduitConfiguration.foundationModels(timeout: 60)

        let description = config.description
        #expect(description.contains("Foundation Models"))
        #expect(description.contains("60"))
    }

    // MARK: - HuggingFace Token Validation

    @Test("empty HuggingFace token throws emptyToken")
    func emptyHuggingFaceTokenThrowsError() throws {
        #expect(throws: ConduitConfigurationError.emptyToken) {
            _ = try ConduitConfiguration.huggingFace(
                token: "",
                model: .huggingFace("test-model")
            )
        }
    }

    @Test("whitespace-only HuggingFace token throws emptyToken")
    func whitespaceOnlyHuggingFaceTokenThrowsError() throws {
        #expect(throws: ConduitConfigurationError.emptyToken) {
            _ = try ConduitConfiguration.huggingFace(
                token: "   \n\t",
                model: .huggingFace("test-model")
            )
        }
    }
}
