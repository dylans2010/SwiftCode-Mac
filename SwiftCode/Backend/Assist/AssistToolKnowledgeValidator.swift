import Foundation
import os

// MARK: - Assist Tool Knowledge Validator
//
// Runtime validation that the behavioral tool documentation in System Assets
// (`AvailableTools.md` catalog + `CallTool.md` procedures) does not drift from
// the actual registered tools in `AssistToolRegistry`:
//   - every registered tool has a catalog entry,
//   - no catalog entry refers to a tool that is not registered,
//   - the mandatory Safeguards.md baseline is present,
//   - the AgentSystemAsset.md index references the expected document set.
//
// The runtime tool registry remains authoritative for tool availability,
// schemas, authorization, and execution; this validator only checks that the
// Markdown documentation is consistent with it.
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
        results.append(await testCatalogPresent())
        results.append(await testAllRegisteredToolsDocumented())
        results.append(await testNoOrphanedToolDocumentation())
        results.append(await testSafeguardsBaselinePresent())
        results.append(await testIndexReferencesExpectedDocuments())
        return results
    }

    // MARK: - Helpers

    private func loadAsset(_ relativePath: String) -> String? {
        SystemIndexService.shared.bundledText(forRelativePath: relativePath)
    }

    /// Parses catalog lines of the form `` - `tool_id` (riskPosture) — description ``
    /// into tool ids in document order. Stops at the Cloud Toolkit section:
    /// those IDs are provided by the Antigravity cloud runtime, not the
    /// registry, and must not be reported as orphans. The ID pattern accepts
    /// `plan-AskUser` (hyphen + uppercase), which the old pattern rejected.
    private func catalogToolIds(in catalog: String) -> [String] {
        var ids: [String] = []
        for line in catalog.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## Cloud Toolkit") { break }
            guard trimmed.hasPrefix("- `") else { continue }
            let afterTick = trimmed.dropFirst(3)
            guard let end = afterTick.firstIndex(of: "`") else { continue }
            let id = String(afterTick[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { continue }
            ids.append(id)
        }
        return ids
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

    private func testCatalogPresent() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let catalog = loadAsset("AvailableTools.md"), !catalog.isEmpty else {
            return result(testName: "Tool Knowledge: Catalog Present", passed: false,
                          message: "AvailableTools.md not found in bundled System Assets.", start: start)
        }
        guard let procedures = loadAsset("CallTool.md"), !procedures.isEmpty else {
            return result(testName: "Tool Knowledge: Catalog Present", passed: false,
                          message: "CallTool.md not found in bundled System Assets.", start: start)
        }
        return result(testName: "Tool Knowledge: Catalog Present", passed: true,
                      message: "Catalog (\(catalog.count) chars) and procedures (\(procedures.count) chars) present.", start: start)
    }

    private func testAllRegisteredToolsDocumented() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let catalog = loadAsset("AvailableTools.md") else {
            return result(testName: "Tool Knowledge: Tools Documented", passed: false,
                          message: "AvailableTools.md unavailable.", start: start)
        }
        let documented = Set(catalogToolIds(in: catalog))
        let registry = AssistToolRegistry()
        let missing = registry.allTools.map(\.id).filter { !documented.contains($0) }.sorted()
        if missing.isEmpty {
            return result(testName: "Tool Knowledge: Tools Documented", passed: true,
                          message: "All \(registry.allTools.count) registered tools documented in AvailableTools.md.", start: start)
        }
        return result(testName: "Tool Knowledge: Tools Documented", passed: false,
                      message: "Undocumented tools: \(missing.joined(separator: ", "))", start: start)
    }

    private func testNoOrphanedToolDocumentation() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let catalog = loadAsset("AvailableTools.md") else {
            return result(testName: "Tool Knowledge: No Orphan Docs", passed: false,
                          message: "AvailableTools.md unavailable.", start: start)
        }
        let documented = catalogToolIds(in: catalog)
        let registry = AssistToolRegistry()
        let registeredIds = Set(registry.allTools.map(\.id))
        let orphans = documented.filter { !registeredIds.contains($0) }.sorted()
        if orphans.isEmpty {
            return result(testName: "Tool Knowledge: No Orphan Docs", passed: true,
                          message: "No catalog entry refers to an unregistered tool.", start: start)
        }
        return result(testName: "Tool Knowledge: No Orphan Docs", passed: false,
                      message: "Orphaned doc entries: \(orphans.joined(separator: ", "))", start: start)
    }

    private func testSafeguardsBaselinePresent() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let safeguards = loadAsset("Safeguards.md"), !safeguards.isEmpty else {
            return result(testName: "Tool Knowledge: Safeguards Baseline", passed: false,
                          message: "Safeguards.md not found in bundled System Assets.", start: start)
        }
        // Sanity: the mandatory baseline must address credentials and
        // destructive operations; an empty/gutted file must not pass silently.
        let lower = safeguards.lowercased()
        let required = ["credential", "destructive"]
        let missing = required.filter { !lower.contains($0) }
        if missing.isEmpty {
            return result(testName: "Tool Knowledge: Safeguards Baseline", passed: true,
                          message: "Safeguards.md present (\(safeguards.count) chars).", start: start)
        }
        return result(testName: "Tool Knowledge: Safeguards Baseline", passed: false,
                      message: "Safeguards.md missing expected topics: \(missing.joined(separator: ", ")).", start: start)
    }

    private func testIndexReferencesExpectedDocuments() async -> RuntimeTestCaseResult {
        let start = Date()
        guard let index = loadAsset("AgentSystemAsset.md"), !index.isEmpty else {
            return result(testName: "Tool Knowledge: Index Coherent", passed: false,
                          message: "AgentSystemAsset.md not found in bundled System Assets.", start: start)
        }
        let expected = ["Identity.md", "Safeguards.md", "CallTool.md", "AvailableTools.md",
                        "Contexts.md", "ErrorHandling.md", "Authentication.md"]
        let missing = expected.filter { !index.contains($0) }
        if missing.isEmpty {
            return result(testName: "Tool Knowledge: Index Coherent", passed: true,
                          message: "AgentSystemAsset.md references all expected documents.", start: start)
        }
        return result(testName: "Tool Knowledge: Index Coherent", passed: false,
                      message: "Index missing references: \(missing.joined(separator: ", ")).", start: start)
    }
}
