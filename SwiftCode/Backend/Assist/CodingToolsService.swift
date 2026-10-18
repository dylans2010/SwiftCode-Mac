import Foundation
import os

/// Canonical Coding Tools service providing contextual editor operations (Refactor, Explain, Document, Preview, Custom).
/// Fully reuses the existing Assist models, system instructions, error recovery, and conversation memory.
@MainActor
public final class CodingToolsService: Sendable {
    public static let shared = CodingToolsService()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "CodingToolsService")

    private init() {}

    /// Canonical system prompt strictly adhered to every time CodingTools generates code.
    public static let codingToolsSystemPrompt: String = """
    You are an expert Swift and Apple platforms software engineer integrated into SwiftCode IDE.
    Your task is to analyze, refactor, explain, document, and generate production-grade Swift and SwiftUI code.

    Core Rules & Directives:
    1. Language & Platform: Target modern Swift 6 with strict concurrency checking. Ensure Sendable compliance, actor isolation, and thread safety.
    2. Code Quality: Follow idiomatic Apple Swift API Design Guidelines. Strive for concise, clean, self-documenting code with clear naming and minimal boilerplate.
    3. Full File Context Awareness: You are provided with the full file context along with the targeted excerpt. Respect and preserve surrounding types, architectural patterns, imports, and dependencies present in the file.
    4. Output Format: When refactoring, generating, documenting, or modifying code, output ONLY the resulting replacement code block. Do NOT include conversational filler, preamble, apologies, or markdown explanations unless explicitly asked (such as for the Explain action).
    5. Safety & Performance: Preserve intended runtime behavior and error handling. Optimize algorithms for macOS/iOS responsiveness and avoid retain cycles with proper memory management ([weak self]).
    6. Modern APIs: Prefer modern Swift and SwiftUI patterns: @Observable, #Preview, async/await, structured concurrency, and native System Foundation frameworks.
    """

    /// The active model configured in Assist.
    public var activeModelID: String {
        return AssistModelManager.shared.selectedModelID
    }

    /// Dispatches prompt using on-device Apple Foundation Models with strict system prompt, with graceful fallback to AgentModelAdapter.
    private func queryWithFoundationModel(
        prompt: String,
        systemPrompt: String = CodingToolsService.codingToolsSystemPrompt,
        stripCodeFences: Bool = true
    ) async throws -> String {
        logger.info("Querying using Apple Foundation Models...")
        if FoundationModels.shared.isEnabled {
            do {
                let response = try await FoundationModels.shared.generatePrivateResponse(
                    prompt: prompt,
                    systemPrompt: systemPrompt
                )
                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    logger.info("Apple Foundation Models successfully generated response.")
                    return stripCodeFences ? cleanCodeBlock(trimmed) : trimmed
                }
            } catch {
                logger.warning("Apple Foundation Models query error: \(error.localizedDescription). Proceeding with fallback model...")
            }
        }

        let promptWithSystemPrompt = """
        [System Directives]:
        \(systemPrompt)

        \(prompt)
        """
        let response = try await AgentModelAdapter.shared.queryModel(prompt: promptWithSystemPrompt, modelId: activeModelID)
        return stripCodeFences ? cleanCodeBlock(response) : response
    }

    // MARK: - Action A: Refactor Code

    public func refactorCode(
        code: String,
        fullFileContent: String? = nil,
        filePath: String,
        instructions: String? = nil,
        language: String = "swift"
    ) async throws -> String {
        logger.info("Executing Refactor Code on \(filePath)...")
        let fullFileContextText: String
        if let full = fullFileContent, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullFileContextText = """
            FULL FILE CONTEXT ('\(filePath)'):
            ```\(language)
            \(full)
            ```
            """
        } else {
            fullFileContextText = "Target File: '\(filePath)'"
        }

        let isSnippet = fullFileContent != nil && fullFileContent != code && !code.isEmpty

        let prompt = """
        \(fullFileContextText)

        \(isSnippet ? "TARGET EXCERPT TO REFACTOR:\n```\(language)\n\(code)\n```" : "CODE TO REFACTOR:\n```\(language)\n\(code)\n```")

        Refactor the target \(language) code excerpt.
        Preserve intended behavior unless explicitly requested.
        Improve readability, performance, safety, concurrency, and modern Swift conventions.
        \(instructions.map { "User instruction: \($0)" } ?? "")

        Respond ONLY with the complete, refactored replacement code block. Do not include conversational fluff.
        """

        return try await queryWithFoundationModel(prompt: prompt, stripCodeFences: true)
    }

    // MARK: - Action B: Add to Assist Context

    public func addToAssistContext(
        code: String,
        fullFileContent: String? = nil,
        filePath: String,
        language: String = "swift"
    ) {
        logger.info("Adding code from \(filePath) to Assist context...")
        var snippet = """
        [Attached Code Excerpt from '\(filePath)' (\(language))]:
        ```\(language)
        \(code)
        ```
        """

        if let full = fullFileContent, full != code, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snippet += """


            [Full File Context for '\(filePath)']:
            ```\(language)
            \(full)
            ```
            """
        }

        AssistConversationMemory.shared.recordFileInspected(filePath)
        let message = AssistMessage(
            role: .user,
            content: "I've attached this code excerpt and full file context for reference:\n\n\(snippet)"
        )
        AssistManager.shared.messages.append(message)
    }

    // MARK: - Action C: Explain Code

    public func explainCode(
        code: String,
        fullFileContent: String? = nil,
        filePath: String,
        language: String = "swift"
    ) async throws -> String {
        logger.info("Explaining code from \(filePath)...")
        let fullFileContextText: String
        if let full = fullFileContent, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullFileContextText = """
            FULL FILE CONTEXT ('\(filePath)'):
            ```\(language)
            \(full)
            ```
            """
        } else {
            fullFileContextText = "Target File: '\(filePath)'"
        }

        let prompt = """
        \(fullFileContextText)

        TARGET CODE EXCERPT TO EXPLAIN:
        ```\(language)
        \(code)
        ```

        You are an expert software engineer.
        Explain the target \(language) code excerpt with full awareness of the surrounding file context.
        Cover:
        1. Primary purpose and role within the enclosing file architecture
        2. Control flow and data transformations
        3. Key types, APIs, and dependencies
        4. Error handling, thread safety, and edge cases

        Provide a concise, technically accurate explanation in clean markdown.
        """

        return try await queryWithFoundationModel(prompt: prompt, stripCodeFences: false)
    }

    // MARK: - Action D: Write Documentation

    public func writeDocumentation(
        code: String,
        fullFileContent: String? = nil,
        filePath: String,
        language: String = "swift"
    ) async throws -> String {
        logger.info("Generating documentation for \(filePath)...")
        let fullFileContextText: String
        if let full = fullFileContent, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullFileContextText = """
            FULL FILE CONTEXT ('\(filePath)'):
            ```\(language)
            \(full)
            ```
            """
        } else {
            fullFileContextText = "Target File: '\(filePath)'"
        }

        let prompt = """
        \(fullFileContextText)

        TARGET CODE TO DOCUMENT:
        ```\(language)
        \(code)
        ```

        Add comprehensive, standard Swift documentation comments (/// or /** */) to the target code.
        Document:
        - Purpose and role of each declaration
        - Parameters (`- Parameter name: description`)
        - Return value (`- Returns: description`)
        - Thrown errors (`- Throws: description`)
        - Important preconditions, side-effects, and concurrency notes

        Respond ONLY with the documented code block.
        """

        return try await queryWithFoundationModel(prompt: prompt, stripCodeFences: true)
    }

    // MARK: - Action E: Generate SwiftUI Preview

    public func generateSwiftUIPreview(
        code: String,
        fullFileContent: String? = nil,
        filePath: String
    ) async throws -> String {
        logger.info("Generating SwiftUI Preview for \(filePath)...")
        let fullFileContextText: String
        if let full = fullFileContent, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullFileContextText = """
            FULL FILE CONTEXT ('\(filePath)'):
            ```swift
            \(full)
            ```
            """
        } else {
            fullFileContextText = "Target File: '\(filePath)'"
        }

        let prompt = """
        \(fullFileContextText)

        TARGET VIEW CODE:
        ```swift
        \(code)
        ```

        Generate or improve a usable `#Preview` block or `PreviewProvider` for the SwiftUI view in the code, with full awareness of dependencies, state models, and structures declared in the file.
        Requirements:
        1. Resolve dependencies with reasonable sample / mock values.
        2. Use modern `#Preview` syntax when possible.
        3. Ensure syntax is valid SwiftUI.
        4. Do not invent non-existent application classes or external modules.

        Respond ONLY with the complete SwiftUI Preview code block.
        """

        return try await queryWithFoundationModel(prompt: prompt, stripCodeFences: true)
    }

    // MARK: - Action F: Custom Instruction

    public func executeCustomInstruction(
        instruction: String,
        code: String,
        fullFileContent: String? = nil,
        filePath: String,
        language: String = "swift"
    ) async throws -> String {
        logger.info("Executing custom instruction on \(filePath): \(instruction)...")
        let fullFileContextText: String
        if let full = fullFileContent, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullFileContextText = """
            FULL FILE CONTEXT ('\(filePath)'):
            ```\(language)
            \(full)
            ```
            """
        } else {
            fullFileContextText = "Target File: '\(filePath)'"
        }

        let prompt = """
        \(fullFileContextText)

        TARGET EXCERPT:
        ```\(language)
        \(code)
        ```

        User Instruction: "\(instruction)"

        Execute the requested operation on the excerpt with full awareness of the surrounding file context.
        If the instruction requests a code change or refactoring, return ONLY the updated replacement code block.
        If the instruction asks a question, analysis, or architectural view, return a clear, technical response.
        """

        let looksLikeCodeChange = instruction.localizedCaseInsensitiveContains("refactor") ||
            instruction.localizedCaseInsensitiveContains("add") ||
            instruction.localizedCaseInsensitiveContains("implement") ||
            instruction.localizedCaseInsensitiveContains("fix") ||
            instruction.localizedCaseInsensitiveContains("change") ||
            instruction.localizedCaseInsensitiveContains("update") ||
            instruction.localizedCaseInsensitiveContains("convert")

        return try await queryWithFoundationModel(prompt: prompt, stripCodeFences: looksLikeCodeChange)
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
