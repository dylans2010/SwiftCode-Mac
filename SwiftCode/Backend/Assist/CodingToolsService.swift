import Foundation
import os

/// Canonical Coding Tools service providing contextual editor operations (Refactor, Explain, Document, Preview, Custom).
/// Fully reuses the existing Assist models, system instructions, error recovery, and conversation memory.
@MainActor
public final class CodingToolsService: Sendable {
    public static let shared = CodingToolsService()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "CodingToolsService")

    private init() {}

    /// The active model configured in Assist.
    public var activeModelID: String {
        return AssistModelManager.shared.selectedModelID
    }

    // MARK: - Action A: Refactor Code

    public func refactorCode(
        code: String,
        filePath: String,
        instructions: String? = nil,
        language: String = "swift"
    ) async throws -> String {
        logger.info("Executing Refactor Code on \(filePath)...")
        let prompt = """
        You are a senior Swift/macOS systems engineer.
        Refactor the following \(language) code excerpt from file '\(filePath)'.
        Preserve intended behavior unless explicitly requested.
        Improve readability, performance, safety, and modern language conventions.
        \(instructions.map { "User instruction: \($0)" } ?? "")

        CODE TO REFACTOR:
        ```\(language)
        \(code)
        ```

        Respond ONLY with the complete, refactored code block. Do not include conversational fluff.
        """

        let response = try await AgentModelAdapter.shared.queryModel(prompt: prompt, modelId: activeModelID)
        return cleanCodeBlock(response)
    }

    // MARK: - Action B: Add to Assist Context

    public func addToAssistContext(
        code: String,
        filePath: String,
        language: String = "swift"
    ) {
        logger.info("Adding code from \(filePath) to Assist context...")
        let snippet = """
        [Attached Code Context from '\(filePath)' (\(language))]:
        ```\(language)
        \(code)
        ```
        """

        AssistConversationMemory.shared.recordFileInspected(filePath)
        let message = AssistMessage(
            role: .user,
            content: "I've attached this code excerpt for context:\n\n\(snippet)"
        )
        AssistManager.shared.messages.append(message)
    }

    // MARK: - Action C: Explain Code

    public func explainCode(
        code: String,
        filePath: String,
        language: String = "swift"
    ) async throws -> String {
        logger.info("Explaining code from \(filePath)...")
        let prompt = """
        You are an expert software engineer.
        Explain the following \(language) code excerpt from '\(filePath)'.
        Cover:
        1. Primary purpose and architecture
        2. Control flow and data transformations
        3. Key types, APIs, and dependencies
        4. Error handling and potential edge cases

        CODE:
        ```\(language)
        \(code)
        ```

        Provide a concise, technically accurate explanation in clean markdown.
        """

        return try await AgentModelAdapter.shared.queryModel(prompt: prompt, modelId: activeModelID)
    }

    // MARK: - Action D: Write Documentation

    public func writeDocumentation(
        code: String,
        filePath: String,
        language: String = "swift"
    ) async throws -> String {
        logger.info("Generating documentation for \(filePath)...")
        let prompt = """
        You are a technical documentation specialist.
        Add comprehensive, standard Swift documentation comments (/// or /** */) to the following \(language) code from '\(filePath)'.
        Document:
        - Purpose and role of each declaration
        - Parameters (`- Parameter name: description`)
        - Return value (`- Returns: description`)
        - Thrown errors (`- Throws: description`)
        - Important preconditions or side-effects

        CODE:
        ```\(language)
        \(code)
        ```

        Respond ONLY with the documented code block.
        """

        let response = try await AgentModelAdapter.shared.queryModel(prompt: prompt, modelId: activeModelID)
        return cleanCodeBlock(response)
    }

    // MARK: - Action E: Generate SwiftUI Preview

    public func generateSwiftUIPreview(
        code: String,
        filePath: String
    ) async throws -> String {
        logger.info("Generating SwiftUI Preview for \(filePath)...")
        let prompt = """
        You are a SwiftUI expert.
        Generate or improve a usable `#Preview` block or `PreviewProvider` for the SwiftUI view in the following code excerpt from '\(filePath)'.
        Requirements:
        1. Resolve dependencies with reasonable sample / mock values.
        2. Use modern `#Preview` syntax when possible.
        3. Ensure syntax is valid SwiftUI.
        4. Do not invent non-existent application classes or external modules.

        CODE:
        ```swift
        \(code)
        ```

        Respond ONLY with the complete SwiftUI Preview code block.
        """

        let response = try await AgentModelAdapter.shared.queryModel(prompt: prompt, modelId: activeModelID)
        return cleanCodeBlock(response)
    }

    // MARK: - Action F: Custom Instruction

    public func executeCustomInstruction(
        instruction: String,
        code: String,
        filePath: String,
        language: String = "swift"
    ) async throws -> String {
        logger.info("Executing custom instruction on \(filePath): \(instruction)...")
        let prompt = """
        You are an autonomous Swift/macOS coding assistant.
        Target File: '\(filePath)'
        User Instruction: "\(instruction)"

        EXCERPT:
        ```\(language)
        \(code)
        ```

        Execute the requested operation on the excerpt.
        If the instruction requests a code change, return ONLY the updated code block.
        If the instruction asks a question or analysis, return a clear, technical response.
        """

        return try await AgentModelAdapter.shared.queryModel(prompt: prompt, modelId: activeModelID)
    }

    // MARK: - Helpers

    private func cleanCodeBlock(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            // Drop initial ```swift or ```
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
        }
        if trimmed.hasSuffix("```") {
            trimmed = String(trimmed.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
