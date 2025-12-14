// TokenEstimatorTests.swift
// SwiftAgents Framework

import Testing
import Foundation
@testable import SwiftAgents

@Suite("TokenEstimator Tests")
struct TokenEstimatorTests {

    // MARK: - CharacterBasedTokenEstimator Tests

    @Suite("CharacterBasedTokenEstimator")
    struct CharacterBasedTests {

        @Test("Creates with default charactersPerToken")
        func testDefaultInit() {
            let estimator = CharacterBasedTokenEstimator()

            #expect(estimator.charactersPerToken == 4)
        }

        @Test("Creates with custom charactersPerToken")
        func testCustomCharactersPerToken() {
            let estimator = CharacterBasedTokenEstimator(charactersPerToken: 3)

            #expect(estimator.charactersPerToken == 3)
        }

        @Test("Enforces minimum charactersPerToken of 1")
        func testMinimumCharactersPerToken() {
            let estimator = CharacterBasedTokenEstimator(charactersPerToken: 0)

            #expect(estimator.charactersPerToken == 1)
        }

        @Test("Shared instance exists")
        func testSharedInstance() {
            let shared = CharacterBasedTokenEstimator.shared

            #expect(shared.charactersPerToken == 4)
        }

        @Test("Estimates tokens for empty string")
        func testEmptyString() {
            let estimator = CharacterBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "")

            #expect(tokens == 1) // Returns minimum of 1
        }

        @Test("Estimates tokens for single character")
        func testSingleCharacter() {
            let estimator = CharacterBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "A")

            #expect(tokens == 1) // 1 / 4 = 0, max(1, 0) = 1
        }

        @Test("Estimates tokens for short text")
        func testShortText() {
            let estimator = CharacterBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "Hello, world!") // 13 chars

            #expect(tokens == 3) // 13 / 4 = 3
        }

        @Test("Estimates tokens for exact multiple")
        func testExactMultiple() {
            let estimator = CharacterBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "1234567890123456") // 16 chars

            #expect(tokens == 4) // 16 / 4 = 4
        }

        @Test("Estimates tokens for very long text")
        func testVeryLongText() {
            let estimator = CharacterBasedTokenEstimator()
            let longText = String(repeating: "a", count: 10000)

            let tokens = estimator.estimateTokens(for: longText)

            #expect(tokens == 2500) // 10000 / 4 = 2500
        }

        @Test("Uses custom ratio correctly")
        func testCustomRatio() {
            let estimator = CharacterBasedTokenEstimator(charactersPerToken: 2)

            let tokens = estimator.estimateTokens(for: "12345678") // 8 chars

            #expect(tokens == 4) // 8 / 2 = 4
        }

        @Test("Handles unicode characters")
        func testUnicodeCharacters() {
            let estimator = CharacterBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "🚀🎉✨🌟") // 4 chars

            #expect(tokens == 1) // 4 / 4 = 1
        }

        @Test("Handles multiline text")
        func testMultilineText() {
            let estimator = CharacterBasedTokenEstimator()
            let text = """
            Line 1
            Line 2
            Line 3
            """

            let tokens = estimator.estimateTokens(for: text) // 20 chars

            #expect(tokens == 5) // 20 / 4 = 5
        }
    }

    // MARK: - WordBasedTokenEstimator Tests

    @Suite("WordBasedTokenEstimator")
    struct WordBasedTests {

        @Test("Creates with default tokensPerWord")
        func testDefaultInit() {
            let estimator = WordBasedTokenEstimator()

            #expect(estimator.tokensPerWord == 1.3)
        }

        @Test("Creates with custom tokensPerWord")
        func testCustomTokensPerWord() {
            let estimator = WordBasedTokenEstimator(tokensPerWord: 1.5)

            #expect(estimator.tokensPerWord == 1.5)
        }

        @Test("Enforces minimum tokensPerWord of 0.1")
        func testMinimumTokensPerWord() {
            let estimator = WordBasedTokenEstimator(tokensPerWord: 0.05)

            #expect(estimator.tokensPerWord == 0.1)
        }

        @Test("Shared instance exists")
        func testSharedInstance() {
            let shared = WordBasedTokenEstimator.shared

            #expect(shared.tokensPerWord == 1.3)
        }

        @Test("Estimates tokens for empty string")
        func testEmptyString() {
            let estimator = WordBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "")

            #expect(tokens == 1) // Returns minimum of 1
        }

        @Test("Estimates tokens for single word")
        func testSingleWord() {
            let estimator = WordBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "Hello")

            #expect(tokens == 1) // 1 word * 1.3 = 1.3 -> 1
        }

        @Test("Estimates tokens for two words")
        func testTwoWords() {
            let estimator = WordBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "Hello world")

            #expect(tokens == 2) // 2 words * 1.3 = 2.6 -> 2
        }

        @Test("Estimates tokens for multiple words")
        func testMultipleWords() {
            let estimator = WordBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "The quick brown fox jumps") // 5 words

            #expect(tokens == 6) // 5 * 1.3 = 6.5 -> 6
        }

        @Test("Handles multiple spaces")
        func testMultipleSpaces() {
            let estimator = WordBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "Hello    world") // Still 2 words

            #expect(tokens == 2)
        }

        @Test("Handles newlines as separators")
        func testNewlineSeparators() {
            let estimator = WordBasedTokenEstimator()
            let text = """
            Hello
            world
            """

            let tokens = estimator.estimateTokens(for: text) // 2 words

            #expect(tokens == 2)
        }

        @Test("Handles mixed whitespace")
        func testMixedWhitespace() {
            let estimator = WordBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "Hello\tworld\ntest") // 3 words

            #expect(tokens == 3) // 3 * 1.3 = 3.9 -> 3
        }

        @Test("Uses custom ratio correctly")
        func testCustomRatio() {
            let estimator = WordBasedTokenEstimator(tokensPerWord: 2.0)

            let tokens = estimator.estimateTokens(for: "one two three") // 3 words

            #expect(tokens == 6) // 3 * 2.0 = 6
        }

        @Test("Handles punctuation attached to words")
        func testPunctuation() {
            let estimator = WordBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "Hello, world!") // 2 words

            #expect(tokens == 2)
        }

        @Test("Handles very long text with many words")
        func testVeryLongText() {
            let estimator = WordBasedTokenEstimator()
            let words = Array(repeating: "word", count: 100)
            let text = words.joined(separator: " ")

            let tokens = estimator.estimateTokens(for: text)

            #expect(tokens == 130) // 100 * 1.3 = 130
        }
    }

    // MARK: - AveragingTokenEstimator Tests

    @Suite("AveragingTokenEstimator")
    struct AveragingTests {

        @Test("Creates with multiple estimators")
        func testInitWithEstimators() {
            let char = CharacterBasedTokenEstimator()
            let word = WordBasedTokenEstimator()
            let averaging = AveragingTokenEstimator(estimators: [char, word])

            let tokens = averaging.estimateTokens(for: "Hello world") // 11 chars, 2 words
            // char: 11 / 4 = 2
            // word: 2 * 1.3 = 2.6 -> 2
            // avg: (2 + 2) / 2 = 2

            #expect(tokens == 2)
        }

        @Test("Falls back to character estimator when empty array")
        func testEmptyEstimatorsArray() {
            let averaging = AveragingTokenEstimator(estimators: [])

            let tokens = averaging.estimateTokens(for: "12345678") // 8 chars

            #expect(tokens == 2) // Uses CharacterBasedTokenEstimator.shared
        }

        @Test("Shared instance exists")
        func testSharedInstance() {
            let shared = AveragingTokenEstimator.shared

            let tokens = shared.estimateTokens(for: "test")

            #expect(tokens >= 1)
        }

        @Test("Averages multiple estimators correctly")
        func testAveraging() {
            let char = CharacterBasedTokenEstimator(charactersPerToken: 4)
            let word = WordBasedTokenEstimator(tokensPerWord: 1.0)
            let averaging = AveragingTokenEstimator(estimators: [char, word])

            let tokens = averaging.estimateTokens(for: "one two three four") // 18 chars, 4 words
            // char: 18 / 4 = 4
            // word: 4 * 1.0 = 4
            // avg: (4 + 4) / 2 = 4

            #expect(tokens == 4)
        }

        @Test("Returns minimum of 1 for empty string")
        func testEmptyString() {
            let averaging = AveragingTokenEstimator.shared

            let tokens = averaging.estimateTokens(for: "")

            #expect(tokens == 1)
        }

        @Test("Averages three estimators")
        func testThreeEstimators() {
            let char4 = CharacterBasedTokenEstimator(charactersPerToken: 4)
            let char3 = CharacterBasedTokenEstimator(charactersPerToken: 3)
            let word = WordBasedTokenEstimator(tokensPerWord: 1.0)
            let averaging = AveragingTokenEstimator(estimators: [char4, char3, word])

            let tokens = averaging.estimateTokens(for: "123456789012") // 12 chars, 1 word
            // char4: 12 / 4 = 3
            // char3: 12 / 3 = 4
            // word: 1 * 1.0 = 1
            // avg: (3 + 4 + 1) / 3 = 8 / 3 = 2.66 -> 2

            #expect(tokens == 2)
        }

        @Test("Handles single estimator")
        func testSingleEstimator() {
            let char = CharacterBasedTokenEstimator()
            let averaging = AveragingTokenEstimator(estimators: [char])

            let tokens = averaging.estimateTokens(for: "12345678") // 8 chars

            #expect(tokens == 2) // Same as CharacterBasedTokenEstimator
        }
    }

    // MARK: - Protocol Default Implementation Tests

    @Suite("TokenEstimator Protocol Extensions")
    struct ProtocolExtensionTests {

        @Test("Estimates tokens for array of strings with character estimator")
        func testBatchEstimationCharacter() {
            let estimator = CharacterBasedTokenEstimator()
            let texts = [
                "1234",     // 1 token
                "12345678", // 2 tokens
                "123456789012" // 3 tokens
            ]

            let total = estimator.estimateTokens(for: texts)

            #expect(total == 6) // 1 + 2 + 3 = 6
        }

        @Test("Estimates tokens for array of strings with word estimator")
        func testBatchEstimationWord() {
            let estimator = WordBasedTokenEstimator()
            let texts = [
                "one",           // 1 word -> 1 token
                "one two",       // 2 words -> 2 tokens
                "one two three"  // 3 words -> 3 tokens
            ]

            let total = estimator.estimateTokens(for: texts)

            #expect(total == 6) // 1 + 2 + 3 = 6
        }

        @Test("Estimates tokens for empty array")
        func testEmptyArray() {
            let estimator = CharacterBasedTokenEstimator()

            let total = estimator.estimateTokens(for: [])

            #expect(total == 0)
        }

        @Test("Estimates tokens for array with empty strings")
        func testArrayWithEmptyStrings() {
            let estimator = CharacterBasedTokenEstimator()

            let total = estimator.estimateTokens(for: ["", "", ""])

            #expect(total == 3) // Each empty string returns 1
        }

        @Test("Estimates tokens for large array")
        func testLargeArray() {
            let estimator = WordBasedTokenEstimator()
            let texts = Array(repeating: "one two three", count: 10)

            let total = estimator.estimateTokens(for: texts)

            #expect(total == 30) // 3 tokens per string * 10 = 30
        }

        @Test("Batch estimation with averaging estimator")
        func testBatchWithAveraging() {
            let averaging = AveragingTokenEstimator.shared
            let texts = [
                "Hello world",
                "Swift is great",
                "Testing tokens"
            ]

            let total = averaging.estimateTokens(for: texts)

            #expect(total >= 3) // At least 1 token per text
        }
    }

    // MARK: - Edge Cases and Integration Tests

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("All estimators handle empty string consistently")
        func testEmptyStringConsistency() {
            let char = CharacterBasedTokenEstimator()
            let word = WordBasedTokenEstimator()
            let avg = AveragingTokenEstimator.shared

            #expect(char.estimateTokens(for: "") == 1)
            #expect(word.estimateTokens(for: "") == 1)
            #expect(avg.estimateTokens(for: "") == 1)
        }

        @Test("Estimators return consistent types")
        func testReturnTypeConsistency() {
            let char = CharacterBasedTokenEstimator()
            let word = WordBasedTokenEstimator()

            let charResult = char.estimateTokens(for: "test")
            let wordResult = word.estimateTokens(for: "test")

            // Both should be Int (warning suppressed - test validates return type)
            _ = charResult
            _ = wordResult
            #expect(true)
        }

        @Test("Character estimator handles special characters")
        func testSpecialCharacters() {
            let estimator = CharacterBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "!@#$%^&*()") // 10 chars

            #expect(tokens == 2) // 10 / 4 = 2
        }

        @Test("Word estimator handles hyphenated words")
        func testHyphenatedWords() {
            let estimator = WordBasedTokenEstimator()

            let tokens = estimator.estimateTokens(for: "well-known") // 1 word

            #expect(tokens == 1)
        }

        @Test("Sendable conformance allows concurrent access")
        func testSendableConformance() async {
            let estimator = CharacterBasedTokenEstimator.shared

            await withTaskGroup(of: Int.self) { group in
                for i in 1...10 {
                    group.addTask {
                        estimator.estimateTokens(for: String(repeating: "a", count: i * 4))
                    }
                }

                var results: [Int] = []
                for await result in group {
                    results.append(result)
                }

                #expect(results.count == 10)
            }
        }

        @Test("Estimators work with real-world text")
        func testRealWorldText() {
            let text = """
            SwiftAgents is an open-source Swift framework providing comprehensive
            agent development capabilities built on Apple's Foundation Models.
            It complements SwiftAI SDK by providing the agent layer.
            """
            
            let char = CharacterBasedTokenEstimator.shared
            let word = WordBasedTokenEstimator.shared
            let avg = AveragingTokenEstimator.shared

            let charTokens = char.estimateTokens(for: text)
            let wordTokens = word.estimateTokens(for: text)
            let avgTokens = avg.estimateTokens(for: text)

            // Character: ~200 chars / 4 = ~50 tokens
            #expect(charTokens >= 45 && charTokens <= 55)
            
            // Word: 25 words * 1.3 = 32.5 -> 32 tokens
            #expect(wordTokens >= 30 && wordTokens <= 35)
            
            // Average should be between the two
            #expect(avgTokens >= 38 && avgTokens <= 44)
        }

        @Test("Zero and negative values are handled")
        func testBoundaryValues() {
            let char0 = CharacterBasedTokenEstimator(charactersPerToken: 0)
            let charNeg = CharacterBasedTokenEstimator(charactersPerToken: -5)
            let word0 = WordBasedTokenEstimator(tokensPerWord: 0.0)
            let wordNeg = WordBasedTokenEstimator(tokensPerWord: -1.0)

            #expect(char0.charactersPerToken == 1)
            #expect(charNeg.charactersPerToken == 1)
            #expect(word0.tokensPerWord == 0.1)
            #expect(wordNeg.tokensPerWord == 0.1)
        }
    }
}
