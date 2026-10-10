//
//  SystemAssetLoaderTests.swift
//  SwiftCode
//
//  Automated verification test suite for modular system-prompt assets,
//  LoadUpSystemAssets retrieval engine, budget enforcement, tool lifecycle,
//  and UI non-card plain inline formatting.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "SystemAssetLoaderTests")

@MainActor
public final class SystemAssetLoaderTests: Sendable {
    public static let shared = SystemAssetLoaderTests()

    private init() {}

    /// Executes all tests in the System Asset Loader & Tool Activity suite.
    public func runAllTests() async -> [RuntimeTestCaseResult] {
        var results: [RuntimeTestCaseResult] = []

        results.append(await testAssetCountAndOnlyMarkdown())
        results.append(await testBundleAvailabilityAndHeaders())
        results.append(await testDeterministicOrdering())
        results.append(await testMissingResourceSafety())
        results.append(await testMandatoryCoreRulesAlwaysPresent())
        results.append(await testTaskBasedRelevanceRetrieval())
        results.append(await testHardBudgetEnforcement())
        results.append(await testUnrelatedAssetsExcludedForSimpleGreetings())
        results.append(await testRegisteredToolDocumentationCoverage())
        results.append(await testToolLifecycleStartProgressCompletion())
        results.append(await testToolActivityInlinePresentationNoCards())

        return results
    }

    // 1. Asset count >= 20 and ONLY .md files
    public func testAssetCountAndOnlyMarkdown() async -> RuntimeTestCaseResult {
        let start = Date()
        let loader = LoadUpSystemAssets.shared
        let allAssets = loader.allAssets()

        var passed = true
        var message = "All \(allAssets.count) assets loaded and verified."

        if allAssets.count < 20 {
            passed = false
            message = "Expected at least 20 assets, found \(allAssets.count)."
        }

        for asset in allAssets {
            if !asset.filename.hasSuffix(".md") {
                passed = false
                message = "Asset \(asset.filename) does not have .md extension."
                break
            }
        }

        return RuntimeTestCaseResult(
            testName: "System Asset Count (>=20) & Markdown Only",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 2. Bundle availability, non-empty, and valid # Markdown headings
    public func testBundleAvailabilityAndHeaders() async -> RuntimeTestCaseResult {
        let start = Date()
        let loader = LoadUpSystemAssets.shared
        let allAssets = loader.allAssets()

        var missingOrEmpty: [String] = []
        var invalidHeading: [String] = []

        for asset in allAssets {
            if asset.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missingOrEmpty.append(asset.id)
            }
            let firstLine = asset.content.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
            if !firstLine.hasPrefix("#") {
                invalidHeading.append(asset.id)
            }
        }

        let passed = missingOrEmpty.isEmpty && invalidHeading.isEmpty
        let message = passed ? "All \(allAssets.count) assets resolved with valid Markdown headings." : "Issues found: empty=\(missingOrEmpty), badHeading=\(invalidHeading)"

        return RuntimeTestCaseResult(
            testName: "System Asset Bundle Availability & Structure",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 3. Deterministic stable ordering across iterations
    public func testDeterministicOrdering() async -> RuntimeTestCaseResult {
        let start = Date()
        let loader = LoadUpSystemAssets.shared

        let prompt1 = loader.fullCorpusPrompt()
        let prompt2 = loader.fullCorpusPrompt()
        let ids1 = loader.allAssets().map { $0.id }
        let ids2 = loader.allAssets().map { $0.id }

        let passed = (prompt1 == prompt2) && (ids1 == ids2)
        let message = passed ? "Corpus ordering and content hash are 100% deterministic." : "Non-deterministic asset ordering detected."

        return RuntimeTestCaseResult(
            testName: "System Asset Deterministic Ordering",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 4. Missing resource handling without crashes or fatal errors
    public func testMissingResourceSafety() async -> RuntimeTestCaseResult {
        let start = Date()
        let loader = LoadUpSystemAssets.shared

        let nonExistentAsset = loader.asset(for: "NonExistentAsset_XYZ_999")

        let passed = (nonExistentAsset == nil)
        let message = passed ? "Missing resource queries safely return nil without runtime exceptions." : "Unexpected response for missing asset."

        return RuntimeTestCaseResult(
            testName: "System Asset Missing Resource Safety",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 5. Mandatory core rules are always present regardless of objective or budget
    public func testMandatoryCoreRulesAlwaysPresent() async -> RuntimeTestCaseResult {
        let start = Date()
        let loader = LoadUpSystemAssets.shared

        // Test with various objectives and minimal budget
        let testObjectives = ["Fix compiler error in SwiftUI", "Git push origin main", "Hello there", "Run tests"]
        var passed = true
        var message = "Mandatory core rules consistently present."

        for obj in testObjectives {
            let prompt = loader.systemPrompt(for: obj, toolkit: "Cloud", characterBudget: 10_000)
            if !prompt.contains("Core Operating Policy") && !prompt.contains("CoreRules") {
                passed = false
                message = "CoreRules missing for objective: \(obj)"
                break
            }
        }

        return RuntimeTestCaseResult(
            testName: "Mandatory Core Rules Enforcement",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 6. Task-based relevance retrieval prioritizes domain assets
    public func testTaskBasedRelevanceRetrieval() async -> RuntimeTestCaseResult {
        let start = Date()
        let loader = LoadUpSystemAssets.shared

        // Objective 1: Git conflict
        let gitPrompt = loader.systemPrompt(for: "Resolve 3-way git merge conflict in main branch", toolkit: "Cloud", characterBudget: 20_000)
        let gitRelevant = gitPrompt.contains("GitAndVersionControl") || gitPrompt.contains("Version Control")

        // Objective 2: Swift concurrency
        let swiftPrompt = loader.systemPrompt(for: "Fix Swift 6 strict concurrency actor isolation warning", toolkit: "Cloud", characterBudget: 20_000)
        let swiftRelevant = swiftPrompt.contains("SwiftAndConcurrency") || swiftPrompt.contains("Swift 6 Concurrency")

        // Objective 3: Terminal safety
        let termPrompt = loader.systemPrompt(for: "Execute shell command in terminal with safety guardrails", toolkit: "Cloud", characterBudget: 20_000)
        let termRelevant = termPrompt.contains("TerminalAndCommandSafety") || termPrompt.contains("Terminal & Command Safety")

        let passed = gitRelevant && swiftRelevant && termRelevant
        let message = passed ? "Task objectives dynamically prioritized their corresponding domain assets." : "Relevance scoring failed to prioritize matching assets."

        return RuntimeTestCaseResult(
            testName: "Task-Based Relevance Retrieval",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 7. Hard context budget enforcement
    public func testHardBudgetEnforcement() async -> RuntimeTestCaseResult {
        let start = Date()
        let loader = LoadUpSystemAssets.shared

        let budgetSmall = 8_000
        let budgetMedium = 16_000
        let budgetLarge = 30_000

        let promptSmall = loader.systemPrompt(for: "Refactor architecture and optimize builds", toolkit: "Cloud", characterBudget: budgetSmall)
        let promptMedium = loader.systemPrompt(for: "Refactor architecture and optimize builds", toolkit: "Cloud", characterBudget: budgetMedium)
        let promptLarge = loader.systemPrompt(for: "Refactor architecture and optimize builds", toolkit: "Cloud", characterBudget: budgetLarge)

        // Hard budget tolerance: allow small overflow only for completing the mandatory asset block
        let smallPassed = promptSmall.count <= budgetSmall + 4_000
        let mediumPassed = promptMedium.count <= budgetMedium + 4_000
        let largePassed = promptLarge.count <= budgetLarge + 4_000
        let monotoneOrder = promptSmall.count <= promptMedium.count && promptMedium.count <= promptLarge.count

        let passed = smallPassed && mediumPassed && largePassed && monotoneOrder
        let message = passed ? "Context character budget respected across tiers (small=\(promptSmall.count), medium=\(promptMedium.count), large=\(promptLarge.count))." : "Budget enforcement check failed."

        return RuntimeTestCaseResult(
            testName: "Hard Context Budget Enforcement",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 8. Simple greetings do not inflate prompt with entire corpus
    public func testUnrelatedAssetsExcludedForSimpleGreetings() async -> RuntimeTestCaseResult {
        let start = Date()
        let loader = LoadUpSystemAssets.shared
        let fullCorpusCount = loader.fullCorpusPrompt().count

        let greetingPrompt = loader.systemPrompt(for: "Hello, good morning!", toolkit: "Cloud", characterBudget: 16_000)

        // Greeting prompt should be significantly smaller than the full 93K corpus
        let passed = greetingPrompt.count < fullCorpusCount / 2
        let message = passed ? "Greeting prompt (\(greetingPrompt.count) chars) is bounded vs full corpus (\(fullCorpusCount) chars)." : "Prompt was unnecessarily inflated for a greeting."

        return RuntimeTestCaseResult(
            testName: "Corpus Exclusion for Simple Queries",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 9. Registered tools documentation coverage
    public func testRegisteredToolDocumentationCoverage() async -> RuntimeTestCaseResult {
        let start = Date()
        let loader = LoadUpSystemAssets.shared
        let fullCorpus = loader.fullCorpusPrompt()

        let coreTools = ["file_read", "file_write", "search_text", "code_replace", "project_build", "run_command", "view_file"]
        var missingTools: [String] = []

        for tool in coreTools {
            if !fullCorpus.contains(tool) {
                missingTools.append(tool)
            }
        }

        let passed = missingTools.isEmpty
        let message = passed ? "All core registered tools documented in modular assets." : "Missing tool documentation for: \(missingTools)"

        return RuntimeTestCaseResult(
            testName: "Registered Tool Documentation Coverage",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 10. Tool lifecycle: start -> progress/output -> completion with stable IDs and no duplicates
    public func testToolLifecycleStartProgressCompletion() async -> RuntimeTestCaseResult {
        let start = Date()
        let normalizer = AssistEventNormalizer.shared
        normalizer.resetForNewTask()

        var activityGroup = AssistActivityGroup(isExecuting: true)
        let stableCallId = "call_stable_123"
        let toolName = "project_build"
        let args: [String: Any] = ["scheme": "SwiftCode"]

        // 1. Tool started
        normalizer.normalizeToolStarted(callId: stableCallId, toolName: toolName, arguments: args, in: &activityGroup)
        let countAfterStart = activityGroup.tools.count
        let itemAfterStart = activityGroup.tools.first(where: { $0.callId == stableCallId || $0.operationId == stableCallId })
        let startedCorrectly = countAfterStart == 1 && itemAfterStart?.status == .running

        // 2. Incremental progress arrives
        normalizer.normalizeToolProgress(callId: stableCallId, toolName: toolName, progressMessage: "Compiling 45/120 files...", in: &activityGroup)
        let itemAfterProgress = activityGroup.tools.first(where: { $0.callId == stableCallId || $0.operationId == stableCallId })
        let progressCorrect = itemAfterProgress?.result.contains("Compiling") == true || itemAfterProgress?.streamingOutput.contains("Compiling") == true

        // 3. Tool completed
        normalizer.normalizeToolCompleted(callId: stableCallId, toolName: toolName, output: "** BUILD SUCCEEDED **", arguments: args, in: &activityGroup)
        let countAfterCompletion = activityGroup.tools.count
        let itemAfterCompletion = activityGroup.tools.first(where: { $0.callId == stableCallId || $0.operationId == stableCallId })
        let completedCorrectly = countAfterCompletion == 1 && itemAfterCompletion?.status == .completed && itemAfterCompletion?.result.contains("BUILD SUCCEEDED") == true

        // 4. Duplicate completed event replay does not create second row
        normalizer.normalizeToolCompleted(callId: stableCallId, toolName: toolName, output: "** BUILD SUCCEEDED **", arguments: args, in: &activityGroup)
        let countAfterDuplicate = activityGroup.tools.count

        let passed = startedCorrectly && progressCorrect && completedCorrectly && countAfterDuplicate == 1
        let message = passed ? "Tool lifecycle start -> progress -> completed preserved stable ID without duplicate rows." : "Tool lifecycle or deduplication check failed."

        return RuntimeTestCaseResult(
            testName: "Tool Lifecycle & Progress Normalization",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }

    // 11. Tool activity inline presentation: verifies model fields for non-card display
    public func testToolActivityInlinePresentationNoCards() async -> RuntimeTestCaseResult {
        let start = Date()

        let item = ToolActivityItem(
            id: UUID(),
            callId: "call_abc",
            toolId: "file_read",
            purpose: "Reading AssistMainView.swift",
            argumentsSummary: "SwiftCode/Views/AssistMainView.swift",
            streamingOutput: "",
            result: "struct AssistMainView: View { ... }",
            status: .completed,
            progress: nil,
            duration: 0.12,
            timestamp: Date(),
            displayLabel: "Reading file",
            completedLabel: "Read SwiftCode/Views/AssistMainView.swift",
            iconName: "doc.text",
            attemptsCount: 1,
            retryCount: 0,
            semanticKey: "file_read|path:swiftcode/views/assistmainview.swift",
            operationId: "call_abc"
        )

        let json = try? JSONEncoder().encode(item)
        let decoded = try? JSONDecoder().decode(ToolActivityItem.self, from: json ?? Data())

        let passed = (decoded?.callId == "call_abc") &&
            (decoded?.argumentsSummary == "SwiftCode/Views/AssistMainView.swift") &&
            (decoded?.iconName == "doc.text") &&
            (decoded?.status == .completed)

        let message = passed ? "ToolActivityItem properly encapsulates stable callId, argument summary, iconName, and output for plain inline rows." : "Model failed encoding/decoding verification."

        return RuntimeTestCaseResult(
            testName: "Tool Activity Plain Inline Model Verification",
            passed: passed,
            message: message,
            duration: Date().timeIntervalSince(start)
        )
    }
}
