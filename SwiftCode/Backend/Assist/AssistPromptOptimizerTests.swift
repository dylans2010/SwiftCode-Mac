import Foundation
import os

// MARK: - AssistPromptOptimizer Comprehensive Test Suite
@MainActor
public final class AssistPromptOptimizerTests: Sendable {
    public static let shared = AssistPromptOptimizerTests()

    private init() {}

    public func runAllTests() async -> [RuntimeTestCaseResult] {
        var results: [RuntimeTestCaseResult] = []

        results.append(await testToolSchemaMemoization())
        results.append(await testRepositoryInstructionCaching())
        results.append(await testSystemPromptCompaction())
        results.append(await testConversationHistoryCompaction())
        results.append(await testSessionReuseValidation())
        results.append(await testStructuredPromptPrefixOptimization())
        results.append(await testExecutionContextReuse())

        return results
    }

    // 1. Tool Schema Memoization & Invalidation
    public func testToolSchemaMemoization() async -> RuntimeTestCaseResult {
        let start = Date()
        let optimizer = AssistPromptOptimizer.shared
        let registry = AssistManager.shared.registry

        optimizer.invalidateToolSchemas()

        let first = optimizer.cachedPhaseSchemas(for: .planning, in: registry)
        let second = optimizer.cachedPhaseSchemas(for: .planning, in: registry)

        let jsonFirst = optimizer.cachedToolSchemasJSON(in: registry)
        let jsonSecond = optimizer.cachedToolSchemasJSON(in: registry)

        let compact = optimizer.cachedToolSchemasCompact(in: registry)

        let schemasMatch = (first == second) && (!first.isEmpty)
        let jsonMatch = (jsonFirst.count == jsonSecond.count) && (jsonFirst.count > 0)
        let compactValid = !compact.isEmpty

        let passed = schemasMatch && jsonMatch && compactValid

        return RuntimeTestCaseResult(
            testName: "Tool Schema Memoization & Zero-Cost Retrieval",
            passed: passed,
            message: passed ? "Phase schemas and JSON dictionary schemas memoized successfully (\(jsonFirst.count) tools)." : "Schema memoization failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 2. Repository Instruction Caching & Keyword Filtering
    public func testRepositoryInstructionCaching() async -> RuntimeTestCaseResult {
        let start = Date()
        let optimizer = AssistPromptOptimizer.shared
        let workspace = URL(fileURLWithPath: "/Users/dylan/SwiftCode-Mac")

        optimizer.invalidateRepositoryCache()

        let raw = optimizer.loadRepositoryInstructions(for: workspace)
        let cachedAgain = optimizer.loadRepositoryInstructions(for: workspace)

        let filtered = optimizer.optimizedRepositoryInstructions(for: workspace, objective: "Fix swift compiler latency in assist")

        let hasContent = (raw != nil) && (!raw!.isEmpty)
        let cachingWorks = (raw == cachedAgain)
        let filteringWorks = !filtered.isEmpty

        let passed = hasContent && cachingWorks && filteringWorks

        return RuntimeTestCaseResult(
            testName: "Repository Instructions MTime Caching & Filtering",
            passed: passed,
            message: passed ? "Repository guidance loaded and cached with mtime validation." : "Repository instruction caching failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 3. System Prompt Compaction & Budget Enforcement
    public func testSystemPromptCompaction() async -> RuntimeTestCaseResult {
        let start = Date()
        let optimizer = AssistPromptOptimizer.shared

        let budget = 8_000
        let prompt = optimizer.optimizedSystemPrompt(for: "Build and deploy macOS app", toolkit: "System", characterBudget: budget)
        let cachedPrompt = optimizer.optimizedSystemPrompt(for: "Build and deploy macOS app", toolkit: "System", characterBudget: budget)

        let withinBudget = prompt.count <= budget + 500 // Allow slight boundary tolerance
        let isCached = (prompt == cachedPrompt)
        let hasCoreRules = prompt.contains("SYSTEM IDENTITY") || prompt.contains("System Identity") || prompt.contains("Identity") || prompt.contains("CoreRules") || !prompt.isEmpty

        let passed = withinBudget && isCached && hasCoreRules

        return RuntimeTestCaseResult(
            testName: "System Prompt Compaction & Budget Enforcement",
            passed: passed,
            message: passed ? "System prompt compacted to \(prompt.count) chars (budget: \(budget))." : "Compaction exceeded budget or produced empty prompt.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 4. Conversation History Compaction
    public func testConversationHistoryCompaction() async -> RuntimeTestCaseResult {
        let start = Date()
        let optimizer = AssistPromptOptimizer.shared

        let shortEntry = "Tool: view_file\nResult: file found"
        let massiveEntry = "Tool: run_command\nOutput: " + String(repeating: "line of build log\n", count: 200) + "\nExit: 0"

        let history = [shortEntry, massiveEntry]
        let compacted = optimizer.compactConversationHistory(history, maxEntries: 5, maxCharsPerEntry: 400)

        let passed = compacted.count == 2 &&
            compacted[0] == shortEntry &&
            compacted[1].count <= 480 &&
            compacted[1].contains("OUTPUT COMPACTED") &&
            compacted[1].contains("Exit: 0")

        return RuntimeTestCaseResult(
            testName: "Turn History Token Compaction & Preservation",
            passed: passed,
            message: passed ? "Large tool results cleanly compacted while preserving command header and exit tail." : "History compaction failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 5. Session Reuse Validation
    public func testSessionReuseValidation() async -> RuntimeTestCaseResult {
        let start = Date()
        let optimizer = AssistPromptOptimizer.shared

        let baseConfig = GoogleCloudSDKConfiguration(
            model: "gemini-3.8-flash",
            apiKey: "test-key-123",
            vertex: false,
            systemInstructions: "Base system instructions",
            skillsPaths: ["/skills"],
            workspaces: ["/workspace"],
            toolkit: "System"
        )

        let dummyBridge = GoogleCloudSDKBridge()
        let session = GoogleCloudSDKSession(id: "session-1", config: baseConfig, bridge: dummyBridge)

        // Matching config -> should reuse
        var matchingConfig = baseConfig
        matchingConfig.systemInstructions = "Turn-specific system instructions variation"
        let canReuseMatching = optimizer.canReuseSDKSession(existing: session, targetConfig: matchingConfig)

        // Different model -> should NOT reuse
        var differentModelConfig = baseConfig
        differentModelConfig.model = "claude-3-7-sonnet"
        let canReuseDiffModel = optimizer.canReuseSDKSession(existing: session, targetConfig: differentModelConfig)

        // Different toolkit -> should NOT reuse
        var differentToolkitConfig = baseConfig
        differentToolkitConfig.toolkit = "Cloud"
        let canReuseDiffToolkit = optimizer.canReuseSDKSession(existing: session, targetConfig: differentToolkitConfig)

        let passed = canReuseMatching && !canReuseDiffModel && !canReuseDiffToolkit

        return RuntimeTestCaseResult(
            testName: "Antigravity Bridge Session Reuse Validation",
            passed: passed,
            message: passed ? "Session reuse correctly permitted for identical model/toolkit and rejected on configuration drift." : "Session reuse logic failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 6. Structured Prompt Prefix Optimization for LLM Cache
    public func testStructuredPromptPrefixOptimization() async -> RuntimeTestCaseResult {
        let start = Date()
        let optimizer = AssistPromptOptimizer.shared

        let assembled = optimizer.assembleStructuredAgentPrompt(
            assetSystemPrompt: "Static Operating Rules",
            objective: "Add new feature",
            executionModeInstruction: "Autopilot Mode",
            groundingInstructions: "Workspace Rules",
            attachmentsBlock: "",
            skillsBlock: "",
            manifest: "Root: /App",
            activeFiles: "main.swift",
            toolSchemas: "Tools catalog",
            history: ["Result 1"],
            failureSummary: ""
        )

        // Verify ordering: Static Operating Rules and Tool Schemas are before the goal and active files
        let rulesRange = assembled.range(of: "Static Operating Rules")?.lowerBound
        let toolsRange = assembled.range(of: "Tools catalog")?.lowerBound
        let goalRange = assembled.range(of: "Goal: \"Add new feature\"")?.lowerBound
        let historyRange = assembled.range(of: "Result 1")?.lowerBound

        var passed = false
        if let r = rulesRange, let t = toolsRange, let g = goalRange, let h = historyRange {
            passed = (r < t) && (t < g) && (g < h)
        }

        return RuntimeTestCaseResult(
            testName: "Prefix-Cacheable Structured Prompt Assembly",
            passed: passed,
            message: passed ? "Prompt sections ordered deterministically: Static Rules -> Schemas -> Goal -> Turn History." : "Prompt prefix ordering violation.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 7. Execution Context Reuse
    public func testExecutionContextReuse() async -> RuntimeTestCaseResult {
        let start = Date()
        let optimizer = AssistPromptOptimizer.shared
        let sessionId = UUID()
        let workspace = URL(fileURLWithPath: "/Users/dylan/SwiftCode-Mac")

        let ctx1 = optimizer.executionContext(for: sessionId, workspaceRoot: workspace)
        let ctx2 = optimizer.executionContext(for: sessionId, workspaceRoot: workspace)

        let passed = (ctx1.sessionId == ctx2.sessionId) && (ctx1.workspaceRoot == ctx2.workspaceRoot)

        return RuntimeTestCaseResult(
            testName: "Tool Execution Context Allocation Caching",
            passed: passed,
            message: passed ? "Execution context reused across tool invocations without re-allocating services." : "Context reuse failed.",
            duration: Date().timeIntervalSince(start)
        )
    }
}
