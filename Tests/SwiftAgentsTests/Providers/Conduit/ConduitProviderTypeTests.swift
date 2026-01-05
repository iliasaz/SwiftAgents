// ConduitProviderTypeTests.swift
// SwiftAgentsTests
//
// Tests for ConduitProviderType enumeration and its functionality.

import Conduit
import Foundation
@testable import SwiftAgents
import Testing

@Suite("ConduitProviderType Tests")
struct ConduitProviderTypeTests {
    // MARK: - Display Name Tests

    @Test("Anthropic provider has correct display name")
    func anthropicProviderHasCorrectDisplayName() {
        let providerType = ConduitProviderType.anthropic(
            model: .claudeSonnet45,
            apiKey: "test"
        )

        #expect(providerType.displayName == "Anthropic")
    }

    @Test("OpenAI provider has correct display name")
    func openAIProviderHasCorrectDisplayName() {
        let providerType = ConduitProviderType.openAI(
            model: .gpt4o,
            apiKey: "test"
        )

        #expect(providerType.displayName == "OpenAI")
    }

    @Test("MLX provider has correct display name")
    func mlxProviderHasCorrectDisplayName() {
        let providerType = ConduitProviderType.mlx(model: .llama3_2_1b)

        #expect(providerType.displayName == "MLX (Local)")
    }

    @Test("HuggingFace provider has correct display name")
    func huggingFaceProviderHasCorrectDisplayName() {
        let providerType = ConduitProviderType.huggingFace(
            model: .huggingFace("meta-llama/Llama-3.1-8B-Instruct"),
            token: "test"
        )

        #expect(providerType.displayName == "HuggingFace")
    }

    @Test("Foundation Models provider has correct display name")
    func foundationModelsProviderHasCorrectDisplayName() {
        let providerType = ConduitProviderType.foundationModels

        #expect(providerType.displayName == "Apple Foundation Models")
    }

    // MARK: - Network Requirements Tests

    @Test("MLX provider does not require network")
    func mlxProviderDoesNotRequireNetwork() {
        let providerType = ConduitProviderType.mlx(model: .llama3_2_1b)

        #expect(providerType.requiresNetwork == false)
        #expect(providerType.isOnDevice == true)
    }

    @Test("Foundation Models provider does not require network")
    func foundationModelsProviderDoesNotRequireNetwork() {
        let providerType = ConduitProviderType.foundationModels

        #expect(providerType.requiresNetwork == false)
        #expect(providerType.isOnDevice == true)
    }

    @Test("Anthropic provider requires network")
    func anthropicProviderRequiresNetwork() {
        let providerType = ConduitProviderType.anthropic(
            model: .claudeSonnet45,
            apiKey: "test"
        )

        #expect(providerType.requiresNetwork == true)
        #expect(providerType.isOnDevice == false)
    }

    @Test("OpenAI provider requires network")
    func openAIProviderRequiresNetwork() {
        let providerType = ConduitProviderType.openAI(
            model: .gpt4o,
            apiKey: "test"
        )

        #expect(providerType.requiresNetwork == true)
        #expect(providerType.isOnDevice == false)
    }

    @Test("HuggingFace provider requires network")
    func huggingFaceProviderRequiresNetwork() {
        let providerType = ConduitProviderType.huggingFace(
            model: .huggingFace("test-model"),
            token: "test"
        )

        #expect(providerType.requiresNetwork == true)
        #expect(providerType.isOnDevice == false)
    }

    // MARK: - Model String Tests

    @Test("Anthropic model string contains model identifier")
    func anthropicModelStringContainsModelIdentifier() {
        let providerType = ConduitProviderType.anthropic(
            model: .claudeSonnet45,
            apiKey: "test"
        )

        #expect(!providerType.modelString.isEmpty)
        #expect(providerType.modelString.contains("claude"))
    }

    @Test("OpenAI model string contains model identifier")
    func openAIModelStringContainsModelIdentifier() {
        let providerType = ConduitProviderType.openAI(
            model: .gpt4o,
            apiKey: "test"
        )

        #expect(!providerType.modelString.isEmpty)
        #expect(providerType.modelString.contains("gpt"))
    }

    @Test("MLX model string is not empty")
    func mlxModelStringIsNotEmpty() {
        let providerType = ConduitProviderType.mlx(model: .llama3_2_1b)

        #expect(!providerType.modelString.isEmpty)
    }

    @Test("HuggingFace model string contains model name")
    func huggingFaceModelStringContainsModelName() {
        let providerType = ConduitProviderType.huggingFace(
            model: .huggingFace("test-hf-model"),
            token: "test"
        )

        #expect(providerType.modelString.contains("test-hf-model"))
    }

    @Test("Foundation Models model string is set")
    func foundationModelsModelStringIsSet() {
        let providerType = ConduitProviderType.foundationModels

        #expect(!providerType.modelString.isEmpty)
    }

    // MARK: - Equatable Tests

    @Test("same Anthropic providers are equal")
    func sameAnthropicProvidersAreEqual() {
        let type1 = ConduitProviderType.anthropic(model: .claudeSonnet45, apiKey: "test")
        let type2 = ConduitProviderType.anthropic(model: .claudeSonnet45, apiKey: "test")

        #expect(type1 == type2)
    }

    @Test("different providers are not equal")
    func differentProvidersAreNotEqual() {
        let type1 = ConduitProviderType.anthropic(model: .claudeSonnet45, apiKey: "test")
        let type2 = ConduitProviderType.openAI(model: .gpt4o, apiKey: "test")

        #expect(type1 != type2)
    }

    @Test("same providers with different API keys are not equal")
    func sameProvidersWithDifferentAPIKeysAreNotEqual() {
        let type1 = ConduitProviderType.anthropic(model: .claudeSonnet45, apiKey: "key1")
        let type2 = ConduitProviderType.anthropic(model: .claudeSonnet45, apiKey: "key2")

        #expect(type1 != type2)
    }

    @Test("same providers with different models are not equal")
    func sameProvidersWithDifferentModelsAreNotEqual() {
        let type1 = ConduitProviderType.openAI(model: .gpt4o, apiKey: "test")
        let type2 = ConduitProviderType.openAI(model: .gpt4oMini, apiKey: "test")

        #expect(type1 != type2)
    }

    @Test("MLX providers with same model are equal")
    func mlxProvidersWithSameModelAreEqual() {
        let type1 = ConduitProviderType.mlx(model: .llama3_2_1b)
        let type2 = ConduitProviderType.mlx(model: .llama3_2_1b)

        #expect(type1 == type2)
    }

    @Test("Foundation Models providers are equal")
    func foundationModelsProvidersAreEqual() {
        let type1 = ConduitProviderType.foundationModels
        let type2 = ConduitProviderType.foundationModels

        #expect(type1 == type2)
    }

    // MARK: - Description Tests

    @Test("Anthropic description contains model info")
    func anthropicDescriptionContainsModelInfo() {
        let providerType = ConduitProviderType.anthropic(
            model: .claudeSonnet45,
            apiKey: "test"
        )

        let description = String(describing: providerType)

        #expect(description.contains("anthropic") || description.contains("Anthropic"))
    }

    @Test("MLX description contains model info")
    func mlxDescriptionContainsModelInfo() {
        let providerType = ConduitProviderType.mlx(model: .llama3_2_1b)

        let description = String(describing: providerType)

        #expect(description.contains("mlx") || description.contains("MLX"))
    }

    // MARK: - Custom Model Tests

    @Test("HuggingFace with custom model works")
    func huggingFaceWithCustomModelWorks() {
        let customModel = ModelIdentifier.huggingFace("custom-org/custom-model")
        let providerType = ConduitProviderType.huggingFace(
            model: customModel,
            token: "test"
        )

        #expect(providerType.modelString.contains("custom-org/custom-model"))
        #expect(providerType.displayName == "HuggingFace")
    }

    @Test("MLX with custom model works")
    func mlxWithCustomModelWorks() {
        let customModel = ModelIdentifier.mlx("custom-org/custom-mlx-model")
        let providerType = ConduitProviderType.mlx(model: customModel)

        #expect(providerType.modelString.contains("custom-org/custom-mlx-model"))
        #expect(providerType.displayName == "MLX (Local)")
    }
}
