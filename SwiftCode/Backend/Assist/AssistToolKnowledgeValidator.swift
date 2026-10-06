import Foundation
import os

// MARK: - Assist Tool Knowledge Validator
//
// Runtime validation that the behavioral tool documentation in
// `AgentSystemAsset.md` (section "TOOL SELECTION & USAGE") does not drift from
// the actual registered tools in `AssistToolRegistry`:
//   - every registered tool has a documented entry,
//   - every required parameter is named in its entry,
//   - no documented entry refers to a tool that is not registered,
//   - the section-extraction helpers round-trip correctly.
//
// Follows the same pattern as `AssistModelRouterTests`: `runAllTests()` returns
// `[RuntimeTestCaseResult]` for aggregation by `AssistRuntimeTestSuite`.

@MainActor
public final class AssistToolKnowledgeValidator: Sendable {
    public static let shared = AssistToolKnowledgeValidator()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistToolKnowledgeValidator")

    private init() {}

    /// Executes all tool-knowledge validation checks.
    public func runAllTests() async -> [RuntimeTestCaseResult] {
        var results: [RuntimeTestCaseResult] = []
        results.append(await testToolSelectionSectionPresent())
        results.append(await testAllRegisteredToolsDocumented())
        results.append(await testRequiredParametersDocumented())
        results.append(await testNoOrphanedToolDocumentation())
        results.append(await testSectionExtractionRoundTrip())
        return results
    }

    // MARK: - Helpers

    private func loadSystemPrompt() -> String? {
        guard let url = Bundle.main.url(forResource: "AgentSystemAsset", withExtension: "md") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func toolSelectionSection(in prompt: String) -> String? {
        AssistSystemPromptSections.extractSection(named: "TOOL SELECTION & USAGE", from: prompt)
    }

    /// Splits the Tool Selection & Usage section into per-tool blocks keyed by
    /// tool id. Blocks run from a `#### \`<id>\`` heading to the next `#### ` or
    /// `## ` heading.
    private func toolBlocks(in section: String) -> [String: String] {
        var blocks: [String: String] = [:]
        let lines = section.components(separatedBy: "\n")
        var currentId: String?
        var currentLines: [String] = []

        func flush() {
            if let id = currentId {
                blocks[id] = currentLines.joined(separator: "\n")
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#### `") && trimmed.hasSuffix("`") {
                flush()
                let id = String(trimmed.dropFirst(6).dropLast(1))
                currentId = id
                currentLines = []
            } else if trimmed.hasPrefix("## ") && currentId != nil {
                flush()
                currentId = nil
                currentLines = []
            } else if currentId != nil {
                currentLines.append(line)
            }
        }
        flush()
        return blocks
    }

    private func result(testName: String, passed: Bool, message: String, start: Date) -> RuntimeTestCaseResult {
        RuntimeTestCaseResult(
            testName: testName,
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // MARK: - Tests

    private func testToolSelectionSectionPresent() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let prompt = loadSystemPrompt() else {
            return result(testName: "Tool Knowledge: Section Present", passed: false,
                          message: "AgentSystemAsset.md not found in bundle.", start: start)
        }
        guard let section = toolSelectionSection(in: prompt), !section.isEmpty else {
            return result(testName: "Tool Knowledge: Section Present", passed: false,
                          message: "TOOL SELECTION & USAGE section missing from AgentSystemAsset.md.", start: start)
        }
        return result(testName: "Tool Knowledge: Section Present", passed: true,
                      message: "Section present (\(section.count) chars).", start: start)
    }

    private func testAllRegisteredToolsDocumented() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let prompt = loadSystemPrompt(),
              let section = toolSelectionSection(in: prompt) else {
            return result(testName: "Tool Knowledge: Tools Documented", passed: false,
                          message: "System prompt or section unavailable.", start: start)
        }
        let blocks = toolBlocks(in: section)
        let registry = AssistToolRegistry()
        let missing = registry.allTools.map(\.id).filter { blocks[$0] == nil }.sorted()
        if missing.isEmpty {
            return result(testName: "Tool Knowledge: Tools Documented", passed: true,
                          message: "All \(registry.allTools.count) registered tools documented.", start: start)
        }
        return result(testName: "Tool Knowledge: Tools Documented", passed: false,
                      message: "Undocumented tools: \(missing.joined(separator: ", "))", start: start)
    }

    private func testRequiredParametersDocumented() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let prompt = loadSystemPrompt(),
              let section = toolSelectionSection(in: prompt) else {
            return result(testName: "Tool Knowledge: Params Documented", passed: false,
                          message: "System prompt or section unavailable.", start: start)
        }
        let blocks = toolBlocks(in: section)
        let registry = AssistToolRegistry()
        var problems: [String] = []
        for tool in registry.allTools {
            guard let block = blocks[tool.id] else { continue }
            let required = tool.parametersSchema.required ?? []
            for param in required where !block.contains("`\(param)`") {
                problems.append("\(tool.id): required param `\(param)` not named in docs")
            }
        }
        if problems.isEmpty {
            return result(testName: "Tool Knowledge: Params Documented", passed: true,
                          message: "All required parameters named in tool docs.", start: start)
        }
        return result(testName: "Tool Knowledge: Params Documented", passed: false,
                      message: problems.joined(separator: "; "), start: start)
    }

    private func testNoOrphanedToolDocumentation() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let prompt = loadSystemPrompt(),
              let section = toolSelectionSection(in: prompt) else {
            return result(testName: "Tool Knowledge: No Orphan Docs", passed: false,
                          message: "System prompt or section unavailable.", start: start)
        }
        let blocks = toolBlocks(in: section)
        let registry = AssistToolRegistry()
        let registeredIds = Set(registry.allTools.map(\.id))
        let orphans = blocks.keys.filter { !registeredIds.contains($0) }.sorted()
        if orphans.isEmpty {
            return result(testName: "Tool Knowledge: No Orphan Docs", passed: true,
                          message: "No documented tool ids are unregistered.", start: start)
        }
        return result(testName: "Tool Knowledge: No Orphan Docs", passed: false,
                      message: "Orphaned doc entries: \(orphans.joined(separator: ", "))", start: start)
    }

    private func testSectionExtractionRoundTrip() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let prompt = loadSystemPrompt() else {
            return result(testName: "Tool Knowledge: Section Extraction", passed: false,
                          message: "AgentSystemAsset.md not found in bundle.", start: start)
        }
        let names = AssistSystemPromptSections.sectionNames(in: prompt)
        guard names.contains("TOOL SELECTION & USAGE") else {
            return result(testName: "Tool Knowledge: Section Extraction", passed: false,
                          message: "sectionNames(in:) did not list TOOL SELECTION & USAGE.", start: start)
        }
        guard let extracted = AssistSystemPromptSections.extractSection(named: "## 5. TOOL SELECTION & USAGE", from: prompt),
              extracted.contains("#### `file_read`") else {
            return result(testName: "Tool Knowledge: Section Extraction", passed: false,
                          message: "extractSection(named:from:) failed to round-trip the tool section.", start: start)
        }
        let missing = AssistSystemPromptSections.extractSection(named: "NO SUCH SECTION", from: prompt)
        guard missing == nil else {
            return result(testName: "Tool Knowledge: Section Extraction", passed: false,
                          message: "extractSection(named:from:) should return nil for unknown sections.", start: start)
        }
        return result(testName: "Tool Knowledge: Section Extraction", passed: true,
                      message: "\(names.count) sections indexed; extraction round-trips.", start: start)
    }
}
