// Landed subset port — SwiftCode-Legacy `SwiftCode/Backend/Assist/AssistRuntimeTestSuite.swift`
// (main bc28f653; Dylan's own code, direct port authorised under MIT).
// Landed in the tree by writer agent F1B (2026-11-06), derived from F1's staged
// full port in `staging-wire/runtime-tests/` (see F1B-DISPOSITIONS.md there).
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/AssistRuntimeTestSuite.swift`).
//
// LANDED SUBSET — 10 of 40 test methods + 1 of 8 sub-suites, each verified
// against the CURRENT tree (2026-11-06, main bc28f653) to touch only types and
// APIs that exist in SwiftCodeAssistant with matching signatures:
//   1  testAgentStateTransitions
//   2  testTaskBudgetEnforcement
//   6  testFailureMemoryAndThrashingDetection
//   9  testPhaseCoordinationAndDependencyGating
//   13 testAgentRepositoryScannerScopePrecedence
//   16 testContinuousMultiGoalTakeoverSafeguards
//   28 testAssistModelEligibilityExecutionValidation
//   29 testAssistModelEligibilityFallbackResolver
//   30 testMuseBridgeModelPreservationAndLocalProxy (one API adaptation — see inline note)
//   31 testSystemAssetsToolRoutingPolicyRulesAThroughJ
//   + AssistToolKnowledgeValidator.shared.runAllTests() sub-suite
// Method bodies below are byte-identical to F1's staged full port (and, except
// for test 30's adaptation, byte-identical to Legacy). No test was simplified,
// mocked, or stubbed. RuntimeTestCaseResult / RuntimeTestSuiteReport are reused
// from RuntimeTestHarness.swift, not redefined.
//
// HELD TESTS — omitted because their types do not exist in SwiftCodeAssistant
// (or live in a target SwiftCodeAssistant cannot import). Add each back, in
// Legacy order, once its blocker lands. Full per-test evidence is in
// staging-wire/runtime-tests/DISPOSITIONS.md (F1) and F1B-DISPOSITIONS.md.
//   3  testToolRouterPhaseFiltering — AssistToolRegistry lives in SwiftCodeMCP; SwiftCodeAssistant cannot import it
//   4  testUnifiedDiffGeneration — AssistDiffEngine missing
//   5  testTargetedReplacementAndConflictDetection — AssistDiffEngine + DiffConflictError missing
//   7  testCompletionContractEvaluation — AssistMemoryGraph, AssistFileSystem, AssistVerificationPipeline missing
//   8  testPathSandboxSecurity — AssistFileSystem missing
//   8b testToolEcosystemFileReadLinesAndGovernance — AssistFileSystem, AssistWorkingDirectoryStore + 10 file tools missing; AssistToolRegistry is SwiftCodeMCP-only
//   10 testAgentNotesLifecycleAndGitExclusion — AgentNotesManager missing
//   11a testArtifactStoreLifecycle — AssistArtifactStore missing
//   11b testArtifactNamingDisplayTitles — AssistArtifactNaming missing
//   11c testRegistryExpansionCount — AssistToolRegistry is SwiftCodeMCP-only (and 272 of its 289 registered tool types are undeclared anywhere)
//   12 testAgentSkillDiscoveryAndMatching — AgentSkillResolver missing
//   14 testAgentModelAdapterCapabilityNegotiationAndJSONRepair — AgentModelAdapter missing
//   15 testAgentTerminalServiceDeveloperDirResolution — AgentTerminalService missing
//   17 testMyersDiffAlgorithmAndLiveStreamer — MyersDiffAlgorithm, LiveDiffStreamer missing
//   18 testOfflineModelFallbackClassificationAndRehydration — OfflineFallbackManager, ModelFallbackState missing
//   19 testAssistWorkersSubsystem — UseWorkersTool lives in SwiftCodeMCP
//   20 testEventNormalizationAndActivityTrajectory — AssistActivityGroup missing
//   21 testAssistIntentClassifier — AssistIntentClassifier + UserIntent missing
//   22 testAssistBuildProjectIncrementalParsing — BuildOutputAccumulator missing
//   23 testEmptyTemplateBlankState — EmptyTemplate missing
//   24 testCodingToolsServiceActions — AssistConversationMemory missing
//   25 testAssistConversationMemory — AssistConversationMemory missing
//   26 testAssistFinderToolsAndAliases — AssistToolRegistry is SwiftCodeMCP-only
//   27 testAssistModelEligibilityPolicyStrictRule — AssistAvailableModel missing
//   32 testUseWorkersResilientDecodingAndStatePropagation — UseWorkersTool lives in SwiftCodeMCP
//   33 testParallelExecutionEngineAndTerminalSessions — AgentTerminalSessionManager, AgentTerminalExecutionSession missing
//   34 testCodingToolsNativeContextMenuPayload — CodingToolsUI lives in SwiftCodeUI; CodingToolMenuPayload missing
//   35 testNativeScreenAndAppInteractionTools — AssistToolRegistry is SwiftCodeMCP-only; AssistTakeScreenrecordTool / AssistUseAppTool undeclared
//   36 testNativeAppInteractionEngine — AssistToolRegistry is SwiftCodeMCP-only; AssistAppInteractionEngine, AccessibleRect, AccessibleUIElementDescriptor missing
//   37 testNaturalLanguageIntentMatrixAndCapabilityCatalog — AssistIntentClassifier + UserIntent missing; AssistToolRegistry is SwiftCodeMCP-only
// HELD SUB-SUITES (7 of 8):
//   ReverseTestSuite, AssistDocsGitHubToolsTestSuite, GoogleCloudSDKTests,
//   AssistProviderTests — exist only in test targets, unreachable from production
//   SystemIndexTestSuite, SDKProviderTests, HermesProviderTests — exist only in
//   Legacy (HermesProviderTests has since landed in SwiftCodeAssistantTests, which
//   is still a test target and therefore still unreachable from production)
// NOTE: F1's staged header listed the subset as "1, 2, 6, 9, 12, 15, 28, 29, 31";
// that was a typo in the staged file — tests 12 and 15 are BLOCKED per F1's own
// table, and the verified subset is 1, 2, 6, 9, 13, 16, 28, 29, 30, 31 as above.
// Static checks only — no Swift toolchain here; never claim a build passed.
// Pre-existing condition on main: SwiftCodeAssistant already contains dangling
// references to UserIntent, AssistActivityGroup and AgentModelAdapter, so the
// target does not compile on main today even without this file (F1 §4).

import Foundation
import os

// MARK: - Assist v3 Runtime Evaluation & Regression Test Suite

@MainActor
public final class AssistRuntimeTestSuite: Sendable {
    public static let shared = AssistRuntimeTestSuite()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistRuntimeTestSuite")

    private init() {}

    /// Executes the landed subset of regression and evaluation checks for the Assist v3 runtime.
    /// Held tests (see header) are added back, in Legacy order, as their blockers land.
    public func runAllTests() async -> RuntimeTestSuiteReport {
        let startTime = Date()
        var results: [RuntimeTestCaseResult] = []

        logger.info("Starting Assist v3 Runtime Test Suite...")

        results.append(await testAgentStateTransitions())
        results.append(await testTaskBudgetEnforcement())
        results.append(await testFailureMemoryAndThrashingDetection())
        results.append(await testPhaseCoordinationAndDependencyGating())
        results.append(await testAgentRepositoryScannerScopePrecedence())
        results.append(await testContinuousMultiGoalTakeoverSafeguards())
        results.append(await testAssistModelEligibilityExecutionValidation())
        results.append(await testAssistModelEligibilityFallbackResolver())
        results.append(await testMuseBridgeModelPreservationAndLocalProxy())
        results.append(await testSystemAssetsToolRoutingPolicyRulesAThroughJ())
        results.append(contentsOf: await AssistToolKnowledgeValidator.shared.runAllTests())

        let duration = Date().timeIntervalSince(startTime)
        let passed = results.filter { $0.passed }.count
        let failed = results.filter { !$0.passed }.count

        logger.info("Test suite complete: \(passed)/\(results.count) passed in \(String(format: "%.3f", duration))s")

        return RuntimeTestSuiteReport(
            totalTests: results.count,
            passedTests: passed,
            failedTests: failed,
            results: results,
            totalDuration: duration
        )
    }

    // 1. Agent State Transitions
    public func testAgentStateTransitions() async -> RuntimeTestCaseResult {
        let start = Date()
        let session = AssistAgentSession()

        // Valid transition flow
        session.transition(to: .receivingRequest, reason: "Testing initial receive")
        session.transition(to: .analyzingRepository, reason: "Testing analysis")
        session.transition(to: .planning, reason: "Testing planning")

        let stateCount = session.state.stateHistory.count
        let passed = session.state.status == .planning && stateCount == 3

        return RuntimeTestCaseResult(
            testName: "Agent State Transitions",
            passed: passed,
            message: passed ? "Transitions recorded accurately with history." : "Failed to record state transitions.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 2. Task Budget Enforcement
    public func testTaskBudgetEnforcement() async -> RuntimeTestCaseResult {
        let start = Date()
        let task = AgentTask(originalRequest: "Test budget limits", budgets: TaskExecutionBudget(maxIterations: 5, maxToolCalls: 10, maxRepeatedFailures: 3))

        let isOverLimit = task.toolHistory.count > task.budgets.maxToolCalls
        let passed = !isOverLimit && task.budgets.maxIterations == 5

        return RuntimeTestCaseResult(
            testName: "Task Budget Enforcement",
            passed: passed,
            message: passed ? "Task budgets configured and verified." : "Budget verification failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 6. Failure Memory & Thrashing Detection
    public func testFailureMemoryAndThrashingDetection() async -> RuntimeTestCaseResult {
        let start = Date()
        var task = AgentTask(originalRequest: "Test failure memory", budgets: TaskExecutionBudget(maxRepeatedFailures: 3))

        let errorMsg = "Cannot find 'SomeType' in scope"
        _ = AssistErrorRecoveryEngine.shared.recordFailure(task: &task, message: errorMsg, iteration: 1)
        _ = AssistErrorRecoveryEngine.shared.recordFailure(task: &task, message: errorMsg, iteration: 2)
        let (_, isThrashing) = AssistErrorRecoveryEngine.shared.recordFailure(task: &task, message: errorMsg, iteration: 3)

        let passed = isThrashing && task.failures.count == 3

        return RuntimeTestCaseResult(
            testName: "Failure Memory & Thrashing Detection",
            passed: passed,
            message: passed ? "Thrashing detected at threshold correctly." : "Thrashing detection failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 9. Phase Coordination & Dependency Gating
    public func testPhaseCoordinationAndDependencyGating() async -> RuntimeTestCaseResult {
        let start = Date()
        let coordinator = AgentPhaseCoordinator.shared
        coordinator.reset()

        // Initial state: 180+ phases initialized
        let initialCount = coordinator.phases.count
        guard initialCount >= 180 else {
            return RuntimeTestCaseResult(
                testName: "Phase Coordination & Dependency Gating",
                passed: false,
                message: "Expected >= 180 phases, got \(initialCount)",
                duration: Date().timeIntervalSince(start)
            )
        }

        // Test dependency gating: Cannot activate Phase 004 without completing Phase 003
        let canActivate004 = coordinator.canStartPhase("PHASE_004_AGENTS_INTERPRETATION")
        coordinator.completePhase("PHASE_001_REPO_INIT", evidence: "Verified root")
        coordinator.completePhase("PHASE_002_GIT_AUDIT", evidence: "Working tree clean")
        coordinator.completePhase("PHASE_003_AGENTS_DISCOVERY", evidence: "Found AGENTS.md")

        let canActivate004After = coordinator.canStartPhase("PHASE_004_AGENTS_INTERPRETATION")
        let activated = coordinator.startPhase("PHASE_004_AGENTS_INTERPRETATION")

        let passed = !canActivate004 && canActivate004After && activated && coordinator.activePhaseId == "PHASE_004_AGENTS_INTERPRETATION"

        return RuntimeTestCaseResult(
            testName: "Phase Coordination & Dependency Gating",
            passed: passed,
            message: passed ? "All \(initialCount) phases registered and dependency gating verified." : "Dependency gating failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 12. Repository Instruction Scope & Precedence
    public func testAgentRepositoryScannerScopePrecedence() async -> RuntimeTestCaseResult {
        let start = Date()
        let scanner = AgentRepositoryScanner.shared
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("repo_test_\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("Sources/SubModule")
        try? FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootAgents = "# Root Rules\nRule 1: Swift 6 concurrency strictly required."
        let subAgents = "# SubModule Rules\nRule 2: Prefer async streams over notifications."

        try? rootAgents.write(to: tempDir.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try? subAgents.write(to: subDir.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)

        scanner.invalidateCache()
        let allInstructions = scanner.discoverInstructions(in: tempDir)
        let targetFile = subDir.appendingPathComponent("Worker.swift")
        let applicable = scanner.governingInstruction(for: targetFile.path, in: allInstructions)

        let passed = allInstructions.count == 2 && applicable?.content.contains("Prefer async streams") == true

        return RuntimeTestCaseResult(
            testName: "Repository Instruction Scope & Precedence",
            passed: passed,
            message: passed ? "Nearest AGENTS.md scoped correctly to target subdirectory." : "Instruction scope precedence failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 15. Continuous Multi-Goal Autonomous Takeover Safeguards
    public func testContinuousMultiGoalTakeoverSafeguards() async -> RuntimeTestCaseResult {
        let start = Date()

        let rootGoal = "Refactor project networking architecture"
        let parentGoal = AssistGoal(
            title: "Implement NetworkSession actor",
            detailedObjective: "Create actor-isolated networking layer",
            status: .completed,
            provenance: GoalProvenance(
                createdReason: "Initial plan",
                evidenceTrigger: "User request",
                relationshipToRoot: "Direct child",
                parentGoalId: nil,
                generationDepth: 0,
                timestamp: Date()
            ),
            dependencies: [],
            expectedOutcome: "Actor compiles"
        )

        // 1. Valid candidate should pass
        let valid = AssistGoalSafeguards.validateCandidate(
            candidateTitle: "Add Unit Tests for NetworkSession",
            candidateObjective: "Write comprehensive unit tests for NetworkSession",
            existingGoals: [parentGoal],
            rootGoal: rootGoal,
            depth: 1,
            consecutiveFailures: 0
        )

        // 2. Duplicate title should fail
        let duplicate = AssistGoalSafeguards.validateCandidate(
            candidateTitle: "Implement NetworkSession actor",
            candidateObjective: "Re-implement the same actor",
            existingGoals: [parentGoal],
            rootGoal: rootGoal,
            depth: 1,
            consecutiveFailures: 0
        )

        // 3. Unrelated goal should fail
        let unrelated = AssistGoalSafeguards.validateCandidate(
            candidateTitle: "Write a cooking recipe for pasta",
            candidateObjective: "Unrelated culinary text",
            existingGoals: [parentGoal],
            rootGoal: rootGoal,
            depth: 1,
            consecutiveFailures: 0
        )

        // 4. Excessive depth should fail
        let tooDeep = AssistGoalSafeguards.validateCandidate(
            candidateTitle: "Deeply nested subtask",
            candidateObjective: "Subtask at excessive depth",
            existingGoals: [parentGoal],
            rootGoal: rootGoal,
            depth: AssistGoalSafeguards.maxDepth + 1,
            consecutiveFailures: 0
        )

        // 5. Consecutive failures threshold should fail
        let failureStall = AssistGoalSafeguards.validateCandidate(
            candidateTitle: "Another follow up",
            candidateObjective: "Another attempt after multiple failures",
            existingGoals: [parentGoal],
            rootGoal: rootGoal,
            depth: 1,
            consecutiveFailures: AssistGoalSafeguards.maxConsecutiveFailures
        )

        let passed = valid.isValid &&
                     !duplicate.isValid &&
                     !unrelated.isValid &&
                     !tooDeep.isValid &&
                     !failureStall.isValid

        return RuntimeTestCaseResult(
            testName: "Continuous Multi-Goal Takeover Safeguards",
            passed: passed,
            message: passed ? "All 5 takeover safeguards (valid, duplicate, relevance, depth, failures) enforced." : "Takeover safeguard validation failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 28. Assist Model Execution Eligibility Validation
    public func testAssistModelEligibilityExecutionValidation() async -> RuntimeTestCaseResult {
        let start = Date()

        // Eligible model passes execution validation
        var eligiblePassed = false
        do {
            try AssistModelEligibilityPolicy.validateExecutionEligibility(
                modelID: "google/gemini-2.0-flash-free",
                onlyUseFreeModels: true
            )
            eligiblePassed = true
        } catch {
            eligiblePassed = false
        }

        // Ineligible model throws AssistModelEligibilityError
        var ineligibleBlocked = false
        do {
            try AssistModelEligibilityPolicy.validateExecutionEligibility(
                modelID: "anthropic/claude-3.5-sonnet",
                onlyUseFreeModels: true
            )
        } catch let err as AssistModelEligibilityError {
            switch err {
            case .ineligibleModel(let id, _):
                ineligibleBlocked = id == "anthropic/claude-3.5-sonnet"
            default:
                ineligibleBlocked = false
            }
        } catch {
            ineligibleBlocked = false
        }

        // Ineligible model succeeds when onlyUseFreeModels is disabled
        var disabledAllowsIneligible = false
        do {
            try AssistModelEligibilityPolicy.validateExecutionEligibility(
                modelID: "anthropic/claude-3.5-sonnet",
                onlyUseFreeModels: false
            )
            disabledAllowsIneligible = true
        } catch {
            disabledAllowsIneligible = false
        }

        let passed = eligiblePassed && ineligibleBlocked && disabledAllowsIneligible
        return RuntimeTestCaseResult(
            testName: "Assist Model Execution Eligibility Validation",
            passed: passed,
            message: passed ? "Execution layer independently blocks ineligible models and permits eligible models." : "Execution eligibility validation failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 29. Assist Model Fallback Strict Eligibility Resolver
    public func testAssistModelEligibilityFallbackResolver() async -> RuntimeTestCaseResult {
        let start = Date()

        let mixedFallbacks = [
            "google/gemini-2.5-pro",
            "openai/gpt-4o",
            "google/gemini-2.0-flash-free",
            "meta/llama-3.3-70b",
            "deepseek/deepseek-free"
        ]

        let filteredFallbacks = AssistModelEligibilityPolicy.filterEligibleModelIDs(
            mixedFallbacks,
            onlyUseFreeModels: true
        )

        let expected = ["google/gemini-2.0-flash-free", "deepseek/deepseek-free"]
        let passed = filteredFallbacks == expected

        return RuntimeTestCaseResult(
            testName: "Assist Model Fallback Strict Eligibility Resolver",
            passed: passed,
            message: passed ? "Fallback candidates filtered strictly to free-only models without leaking paid models." : "Fallback resolver eligibility filtering failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 30. Muse Bridge Model Preservation & Local Proxy Server
    public func testMuseBridgeModelPreservationAndLocalProxy() async -> RuntimeTestCaseResult {
        let start = Date()

        let proxy = MuseLocalProxyServer()
        var startedSuccessfully = false
        do {
            // Destination adaptation (SwiftCodeAssistant/MuseOtherModelsBridge.swift:507):
            // start() is synchronous and requires the active model resolution plus a
            // streamChat backend; Legacy's no-arg async start() had neither. This
            // test exercises proxy lifecycle only (start -> isRunning -> stop) and
            // never issues a proxied chat call, so the backend closure fails loudly
            // if ever invoked instead of faking model output.
            let resolution = MuseOtherModelResolution(
                modelID: "mistral/mistral-7b-free",
                displayName: "Mistral 7B Free",
                provider: "mistral"
            )
            _ = try proxy.start(active: resolution) { _, _, _ in
                AsyncThrowingStream<String, Error>(unfolding: {
                    throw NSError(
                        domain: "AssistRuntimeTestSuite",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Test harness provides no model backend for the local proxy."]
                    )
                })
            }
            startedSuccessfully = proxy.isRunning
            proxy.stop()
        } catch {
            startedSuccessfully = false
        }
        let stoppedSuccessfully = !proxy.isRunning

        // Test free-model enforcement in bridge context
        var eligibleAllowed = false
        do {
            try AssistModelEligibilityPolicy.validateExecutionEligibility(
                modelID: "mistral/mistral-7b-free",
                onlyUseFreeModels: true
            )
            eligibleAllowed = true
        } catch {
            eligibleAllowed = false
        }

        var ineligibleBlocked = false
        do {
            try AssistModelEligibilityPolicy.validateExecutionEligibility(
                modelID: "mistral/mistral-large-2411",
                onlyUseFreeModels: true
            )
        } catch {
            ineligibleBlocked = true
        }

        let passed = (startedSuccessfully || stoppedSuccessfully) && eligibleAllowed && ineligibleBlocked
        return RuntimeTestCaseResult(
            testName: "Muse Bridge Model Preservation & Local Proxy Server",
            passed: passed,
            message: passed ? "Local proxy server lifecycle, URL generation, and execution validation verified." : "Muse bridge proxy or state failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 31. System Assets Tool Routing Policy (Rules A–J)
    public func testSystemAssetsToolRoutingPolicyRulesAThroughJ() async -> RuntimeTestCaseResult {
        let start = Date()

        let baseline = SystemIndexService.shared.baselinePrompt()

        // Verify tool routing policy rules A through J in baseline prompt
        let hasRuleA = baseline.contains("Rule A") || baseline.contains("Native Tools")
        let hasRuleB = baseline.contains("Rule B") || baseline.contains("Explicit Tool Requests")
        let hasRuleC = baseline.contains("Rule C") || baseline.contains("Task to Tool")
        let hasRuleD = baseline.contains("Rule D") || baseline.contains("Unrelated Calls")
        let hasRuleJ = baseline.contains("Rule J") || baseline.contains("Report Genuine Blockers")

        let passed = hasRuleA && hasRuleB && hasRuleC && hasRuleD && hasRuleJ
        return RuntimeTestCaseResult(
            testName: "System Assets Tool Routing Policy (Rules A–J)",
            passed: passed,
            message: passed ? "Tool routing policy with Rules A through J verified in active system prompt baseline." : "System Assets tool routing policy missing or incomplete.",
            duration: Date().timeIntervalSince(start)
        )
    }
}
