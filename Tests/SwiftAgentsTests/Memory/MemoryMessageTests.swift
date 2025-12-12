// MemoryMessageTests.swift
// SwiftAgents Framework Tests

import Testing
import Foundation
@testable import SwiftAgents

@Suite("MemoryMessage Tests")
struct MemoryMessageTests {

    // MARK: - Initialization Tests

    @Test("Creates message with all parameters")
    func testFullInitialization() {
        let id = UUID()
        let timestamp = Date()
        let metadata = ["key": "value"]

        let message = MemoryMessage(
            id: id,
            role: .user,
            content: "Hello",
            timestamp: timestamp,
            metadata: metadata
        )

        #expect(message.id == id)
        #expect(message.role == .user)
        #expect(message.content == "Hello")
        #expect(message.timestamp == timestamp)
        #expect(message.metadata == metadata)
    }

    @Test("Creates message with default parameters")
    func testDefaultInitialization() {
        let message = MemoryMessage(role: .assistant, content: "Hi there")

        #expect(message.role == .assistant)
        #expect(message.content == "Hi there")
        #expect(message.metadata.isEmpty)
        // ID and timestamp should be auto-generated
        #expect(message.id != UUID())
    }

    // MARK: - Factory Methods Tests

    @Test("User factory method creates correct role")
    func testUserFactory() {
        let message = MemoryMessage.user("Hello world")

        #expect(message.role == .user)
        #expect(message.content == "Hello world")
    }

    @Test("Assistant factory method creates correct role")
    func testAssistantFactory() {
        let message = MemoryMessage.assistant("I can help")

        #expect(message.role == .assistant)
        #expect(message.content == "I can help")
    }

    @Test("System factory method creates correct role")
    func testSystemFactory() {
        let message = MemoryMessage.system("You are helpful")

        #expect(message.role == .system)
        #expect(message.content == "You are helpful")
    }

    @Test("Tool factory method creates correct role and metadata")
    func testToolFactory() {
        let message = MemoryMessage.tool("Result: 42", toolName: "calculator")

        #expect(message.role == .tool)
        #expect(message.content == "Result: 42")
        #expect(message.metadata["tool_name"] == "calculator")
    }

    @Test("Factory methods accept metadata")
    func testFactoryWithMetadata() {
        let message = MemoryMessage.user("Hello", metadata: ["source": "test"])

        #expect(message.metadata["source"] == "test")
    }

    // MARK: - Formatted Content Tests

    @Test("Formatted content includes role prefix")
    func testFormattedContent() {
        let userMessage = MemoryMessage.user("Hello")
        let assistantMessage = MemoryMessage.assistant("Hi")

        #expect(userMessage.formattedContent == "[user]: Hello")
        #expect(assistantMessage.formattedContent == "[assistant]: Hi")
    }

    // MARK: - Role Tests

    @Test("All roles are accessible")
    func testAllRoles() {
        let roles: [MemoryMessage.Role] = [.user, .assistant, .system, .tool]

        #expect(roles.count == 4)
        #expect(MemoryMessage.Role.allCases.count == 4)
    }

    @Test("Role raw values are correct")
    func testRoleRawValues() {
        #expect(MemoryMessage.Role.user.rawValue == "user")
        #expect(MemoryMessage.Role.assistant.rawValue == "assistant")
        #expect(MemoryMessage.Role.system.rawValue == "system")
        #expect(MemoryMessage.Role.tool.rawValue == "tool")
    }

    // MARK: - Codable Tests

    @Test("Message encodes and decodes correctly")
    func testCodable() throws {
        let original = MemoryMessage.user("Test message", metadata: ["key": "value"])

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MemoryMessage.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.role == original.role)
        #expect(decoded.content == original.content)
        #expect(decoded.metadata == original.metadata)
    }

    // MARK: - Equatable Tests

    @Test("Messages with same ID are equal")
    func testEquatable() {
        let id = UUID()
        let message1 = MemoryMessage(id: id, role: .user, content: "Hello")
        let message2 = MemoryMessage(id: id, role: .user, content: "Hello")

        #expect(message1 == message2)
    }

    @Test("Messages with different IDs are not equal")
    func testNotEqual() {
        let message1 = MemoryMessage.user("Hello")
        let message2 = MemoryMessage.user("Hello")

        #expect(message1 != message2)
    }

    // MARK: - Hashable Tests

    @Test("Messages can be used in sets")
    func testHashable() {
        let message1 = MemoryMessage.user("Hello")
        let message2 = MemoryMessage.user("World")

        var set: Set<MemoryMessage> = []
        set.insert(message1)
        set.insert(message2)
        set.insert(message1) // Duplicate

        #expect(set.count == 2)
    }

    // MARK: - Description Tests

    @Test("Description is human-readable")
    func testDescription() {
        let message = MemoryMessage.user("Hello world")
        let description = message.description

        #expect(description.contains("user"))
        #expect(description.contains("Hello world"))
    }

    @Test("Description truncates long content")
    func testDescriptionTruncation() {
        let longContent = String(repeating: "a", count: 100)
        let message = MemoryMessage.user(longContent)
        let description = message.description

        #expect(description.contains("..."))
        #expect(description.count < 100)
    }
}
