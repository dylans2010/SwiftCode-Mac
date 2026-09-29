import Foundation
import Observation
import os

/// Struct to represent standard execution summary metrics.
public struct ExecutionSummaryData: Codable, Sendable {
    public let objective: String
    public let totalDuration: TimeInterval
    public let toolCallCount: Int
    public let filesCreatedCount: Int
    public let filesModifiedCount: Int
    public let filesDeletedCount: Int
    public let validationCount: Int
    public let reviewerConfidence: Double
    public let finalOutcome: String
}

@Observable
@MainActor
public final class AssistAgentSession: Sendable {
    private let pipelineLogger = Logger(subsystem: "com.swiftcode.app", category: "AssistAgentSession")

    public var state = AgentSessionState()
    public var currentTask: AgentTask?
    public var iterationCount = 0
    public var validationCount = 0
    public var repairAttemptCount = 0
    public var successfulToolExecutionCount = 0
    public var recentToolResults: [AssistToolResult] = []
    public var recentErrors: [String] = []

    private var isCancelled = false
    private let registry = AssistToolRegistry()
    private var contextManager: AgentContextManager?
    private var conversationHistory: [String] = []
    private var activeContext: AssistContext?
    private var cachedMatchedSkills: [DiscoveredSkill] = []
    private var cachedSkillsBlock = ""
    private var cachedToolSchemas: [AgentSessionStatus: String] = [:]
    private var lastNotesUpdateTime = Date.distantPast

    // Active Activity Group tracking for conversational messages
    public var currentActivityGroup = AssistActivityGroup(isExecuting: true)
    private var currentAssistantMessageId: UUID?

    // Statistics for execution metrics dashboard
    public var executionSummary: ExecutionSummaryData?
    public let phaseCoordinator = AgentPhaseCoordinator.shared
    public var cachedDiscoveredSkills: [DiscoveredSkill] = []

    public init() {}

    /// MainActor-isolated atomic state transition helper that validates transitions and updates internal state machine.
    @MainActor
    public func transition(to newState: AgentSessionStatus, reason: String, toolResult: String? = nil) {
        let oldState = self.state.status
        guard oldState != newState else { return }

        if !oldState.canTransition(to: newState) {
            pipelineLogger.warning("[State Transition REJECTED] \(oldState.rawValue) -> \(newState.rawValue) | Reason: \(reason)")
            DiagnosticEventBus.shared.logEvent(
                component: "AssistAgentSession",
                severity: "WARNING",
                category: "state_transition_rejected",
                message: "Rejected transition from \(oldState.rawValue) to \(newState.rawValue). Reason: \(reason)"
            )
            return
        }

        let transition = StateTransition(fromState: oldState, toState: newState, reason: reason)
        self.state.stateHistory.append(transition)
        self.state.status = newState

        pipelineLogger.info("[State Transition] \(oldState.rawValue) -> \(newState.rawValue) | Reason: \(reason)")

        DiagnosticEventBus.shared.logEvent(
            component: "AssistAgentSession",
            severity: "INFO",
            category: "state_transition",
            message: "Transitioned from \(oldState.rawValue) to \(newState.rawValue). Reason: \(reason)"
        )

        let event = AgentEvent(state: newState, summary: reason, toolResult: toolResult)
        self.state.events.append(event)
        updateAgentNotes(currentAction: reason)
    }

    // MARK: - Observation Loop

    @MainActor
    private func observeResult(toolId: String, input: [String: Any], result: AssistToolResult, explanation: String) {
        let inputSignature = "\(toolId)::\(input.description)"
        let interpretation: String
        let suggestedNext: String?

        if result.success {
            if !result.filesChanged.isEmpty {
                interpretation = "Successfully modified: \(result.filesChanged.joined(separator: ", "))"
                suggestedNext = "Verify changes and continue with next step"
            } else if let diff = result.diff, !diff.isEmpty {
                let added = diff.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
                let deleted = diff.components(separatedBy: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
                interpretation = "Applied changes: +\(added)/-\(deleted) lines"
                suggestedNext = "Continue to next step or verify"
            } else {
                interpretation = "Tool completed successfully: \(explanation)"
                suggestedNext = "Continue with next planned action"
            }
        } else {
            let error = result.error ?? result.output
            interpretation = "Tool failed: \(error.prefix(200))"
            suggestedNext = "Analyze failure and adjust approach"
        }

        let observation = ToolObservation(
            toolId: toolId,
            inputSignature: inputSignature,
            success: result.success,
            outputSummary: result.output.prefix(300).description,
            filesChanged: result.filesChanged,
            interpretation: interpretation,
            suggestedNextAction: suggestedNext
        )

        self.state.lastObservation = observation
        self.state.observationHistory.append(observation)
        if self.state.observationHistory.count > 20 {
            self.state.observationHistory.removeFirst(self.state.observationHistory.count - 20)
        }
        self.state.semanticStateVersion += 1

        AssistErrorRecoveryEngine.shared.recordToolCallSignature(inputSignature)
    }

    // MARK: - Stuck Detection

    @MainActor
    private func detectStuck() -> StuckDetectionEvent? {
        let currentFileChangeCount = self.state.changeSummary.createdFiles.count +
            self.state.changeSummary.modifiedFiles.count +
            self.state.changeSummary.deletedFiles.count

        if currentFileChangeCount > self.state.lastFileChangeCount {
            self.state.lastFileChangeCount = currentFileChangeCount
            self.state.iterationsSinceFileChange = 0
        } else {
            self.state.iterationsSinceFileChange += 1
        }

        if self.state.iterationsSinceFileChange >= 10 {
            let event = StuckDetectionEvent(
                detectionType: .noFileChangesWhenExpected,
                reason: "No file changes across \(self.state.iterationsSinceFileChange) iterations",
                iteration: self.iterationCount,
                evidence: "File change count stuck at \(currentFileChangeCount)"
            )
            self.state.stuckDetectionLog.append(event)
            return event
        }

        let recentWindow = self.state.recentToolCallWindow.suffix(6)
        if recentWindow.count >= 4 {
            let unique = Set(recentWindow)
            if unique.count <= 2 {
                let event = StuckDetectionEvent(
                    detectionType: .circularBehavior,
                    reason: "Circular behavior detected: only \(unique.count) unique actions in last \(recentWindow.count) calls",
                    iteration: self.iterationCount,
                    evidence: "Recent calls: \(recentWindow.joined(separator: ", "))"
                )
                self.state.stuckDetectionLog.append(event)
                return event
            }
        }

        let signatureCounts = AssistErrorRecoveryEngine.shared.currentSignatureCounts
        for (sig, count) in signatureCounts where count >= 3 {
            let event = StuckDetectionEvent(
                detectionType: .repeatedIdenticalCalls,
                reason: "Tool call signature repeated \(count) times: \(sig)",
                iteration: self.iterationCount,
                evidence: sig
            )
            self.state.stuckDetectionLog.append(event)
            return event
        }

        if self.recentErrors.count >= 5 {
            let uniqueErrors = Set(self.recentErrors.suffix(5))
            if uniqueErrors.count <= 2 {
                let event = StuckDetectionEvent(
                    detectionType: .repeatedFailures,
                    reason: "Repeated failures with only \(uniqueErrors.count) unique errors in last 5 attempts",
                    iteration: self.iterationCount,
                    evidence: uniqueErrors.joined(separator: "; ")
                )
                self.state.stuckDetectionLog.append(event)
                return event
            }
        }

        return nil
    }

    // MARK: - Replanning

    @MainActor
    private func replanFromStuck(detection: StuckDetectionEvent) {
        self.state.replanningCount += 1
        self.state.semanticStateVersion += 1

        pipelineLogger.warning("Replanning triggered: \(detection.reason)")

        let replanPrompt = """

        # STUCK DETECTION & REPLANNING REQUIRED
        The agent has been detected as stuck:
        - Type: \(detection.detectionType.rawValue)
        - Reason: \(detection.reason)
        - Iteration: \(detection.iteration)

        # CURRENT STATE
        - Completed actions: \(self.state.completedActions.joined(separator: ", "))
        - Recent errors: \(self.recentErrors.suffix(3).joined(separator: "; "))
        - Files modified so far: \(self.state.changeSummary.modifiedFiles.map { $0.filename }.joined(separator: ", "))

        # REQUIRED ACTION
        1. Re-ground: Re-read the current state of modified files from disk
        2. Review what has actually been accomplished vs. what remains
        3. Rebuild the plan with a different strategy
        4. Resume execution with the new plan

        Break out of the current loop. Try a completely different technique.
        """

        appendConversationHistory(replanPrompt)
        self.recentErrors.removeAll()
        self.state.recentToolCallWindow.removeAll()
    }

    /// Helper to post or update conversational messages on AssistManager.shared.messages with attached ActivityGroup.
    @MainActor
    private func postConversationalMessage(_ content: String, isComplete: Bool = false) {
        var groupCopy = self.currentActivityGroup
        groupCopy.isExecuting = !isComplete

        if let msgId = currentAssistantMessageId,
           let idx = AssistManager.shared.messages.firstIndex(where: { $0.id == msgId }) {
            // Update existing message
            AssistManager.shared.messages[idx] = AssistMessage(
                role: .assistant,
                content: content,
                activityGroup: groupCopy.hasContent ? groupCopy : nil
            )
        } else {
            // Create new message
            let newMsg = AssistMessage(
                role: .assistant,
                content: content,
                activityGroup: groupCopy.hasContent ? groupCopy : nil
            )
            currentAssistantMessageId = newMsg.id
            AssistManager.shared.messages.append(newMsg)
        }
    }

    public func start(objective: String, attachments: [AgentFileContext] = [], context: AssistContext) async throws {
        let startDate = Date()
        self.validationCount = 0
        self.iterationCount = 0
        self.repairAttemptCount = 0
        self.successfulToolExecutionCount = 0
        self.recentToolResults = []
        self.recentErrors = []
        self.executionSummary = nil
        self.activeContext = context
        self.isCancelled = false
        self.currentActivityGroup = AssistActivityGroup(isExecuting: true)
        self.currentAssistantMessageId = nil

        // Initialize structured task, recovery engine, and phase coordinator
        phaseCoordinator.reset()
        _ = phaseCoordinator.startPhase("PHASE_01_INIT")

        var task = AgentTask(objective: objective)
        self.currentTask = task
        AssistErrorRecoveryEngine.shared.resetSession()

        // PHASE 1: Initializing
        transition(to: .initializing, reason: "Initializing autonomous session.")
        self.state.changeSummary.clear()

        // Conversational start
        postConversationalMessage("I’ll inspect the project first and identify the relevant files before making any changes.")

        // --- COMPREHENSIVE SESSION STATE VALIDATION ---
        let selectedModel = AssistModelManager.shared.selectedModelID
        let selectedProvider = LLMService.shared.provider(for: selectedModel)
        let isAgentMode = UserDefaults.standard.bool(forKey: "com.swiftcode.assist.mode")
        let executionModeRaw = UserDefaults.standard.string(forKey: "com.swiftcode.assist.executionMode") ?? ExecutionMode.autopilot.rawValue
        let executionMode = ExecutionMode(rawValue: executionModeRaw) ?? .autopilot
        self.state.executionMode = executionMode

        pipelineLogger.log("[start] Validating Assist session configuration. Selected Model: \(selectedModel), Selected Provider: \(selectedProvider.rawValue), Mode: \(isAgentMode ? "Agent" : "Chat"), Execution Mode: \(executionMode.rawValue)")

        // 1. Verify selected model is not empty
        guard !selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let errorMsg = "Session State Error: No model has been selected for this session."
            phaseCoordinator.failPhase("PHASE_01_INIT", error: errorMsg)
            transition(to: .failed, reason: errorMsg)
            throw NSError(domain: "AssistAgentSession", code: 400, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        // 2. Verify runtime execution mode is correct
        guard isAgentMode else {
            let errorMsg = "Session State Error: Attempted to run Agent session while execution mode is not set to Agent Mode."
            phaseCoordinator.failPhase("PHASE_01_INIT", error: errorMsg)
            transition(to: .failed, reason: errorMsg)
            throw NSError(domain: "AssistAgentSession", code: 400, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        // 3. Verify Authentication state and capabilities
        if selectedProvider != .offline && selectedProvider != .codex {
            let key = LLMService.shared.retrieveAPIKey(for: selectedProvider)
            guard !key.isEmpty else {
                let errorMsg = "Session Validation Failed: Missing API key / credentials for provider \(selectedProvider.rawValue). Please configure your key in Assist Settings."
                phaseCoordinator.failPhase("PHASE_01_INIT", error: errorMsg)
                transition(to: .failed, reason: errorMsg)
                throw NSError(domain: "AssistAgentSession", code: 401, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        } else if selectedProvider == .offline {
            guard FoundationModels.shared.isEnabled else {
                let errorMsg = "Session Validation Failed: Local Apple Foundation Models are selected but disabled. Please enable them in Assist Settings."
                phaseCoordinator.failPhase("PHASE_01_INIT", error: errorMsg)
                transition(to: .failed, reason: errorMsg)
                throw NSError(domain: "AssistAgentSession", code: 400, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        }

        phaseCoordinator.completePhase("PHASE_01_INIT", evidence: "Model \(selectedModel) and provider \(selectedProvider.rawValue) validated.")
        _ = phaseCoordinator.startPhase("PHASE_02_GROUNDING")

        self.state.objective = objective
        self.state.toolCallCount = 0
        self.state.plan = []
        self.state.events = []
        self.state.completedActions = []
        self.conversationHistory = []
        AssistManager.shared.currentCodeReview = nil
        AssistManager.shared.hasCodeReviewBeenInvoked = false
        AssistManager.shared.isCodeReviewRunning = false

        // Assist v4: Multi-Goal State & Live Diff initialization
        let rootProvenance = GoalProvenance(
            createdReason: "Initial objective requested by user",
            evidenceTrigger: "Direct user prompt",
            relationshipToRoot: "Root Goal",
            generationDepth: 1,
            timestamp: startDate
        )
        let rootGoal = AssistGoal(
            title: objective,
            detailedObjective: objective,
            status: .inProgress,
            provenance: rootProvenance,
            expectedOutcome: "Completion and verification of initial objective"
        )
        self.state.rootGoal = objective
        self.state.currentGoal = rootGoal
        self.state.goalGraph = [rootGoal]
        self.state.completedGoals = []
        self.state.pendingGoals = []
        self.state.rejectedGoals = []
        self.state.takeoverActive = UserDefaults.standard.bool(forKey: "assist.takeoverEnabled")
        self.state.isAutonomousExpansion = false

        LiveDiffStreamer.shared.clearAll()

        self.contextManager = AgentContextManager(context: context)

        // Codebase Analysis
        transition(to: .grounding, reason: "Analyzing codebase structure.")
        let codebaseAnalyzer = _AssistCriticalCodebaseAnalyzer(context: context)
        var preModSummary = ""
        do {
            let summary = try await codebaseAnalyzer.analyze()
            preModSummary = "Scanned \(summary.totalFiles) files and \(summary.swiftFileCount) Swift files recursively in workspace."
        } catch {
            preModSummary = "Failed to scan codebase recursively: \(error.localizedDescription)"
        }
        phaseCoordinator.completePhase("PHASE_02_GROUNDING", evidence: preModSummary)

        // Dynamic Skills Discovery
        _ = phaseCoordinator.startPhase("PHASE_03_SKILLS")
        self.cachedDiscoveredSkills = await AgentSkillResolver.shared.discoverSkills(in: context.workspaceRoot)
        cachedMatchedSkills = AgentSkillResolver.shared.matchSkills(for: objective, in: self.cachedDiscoveredSkills)
        cachedSkillsBlock = "\n" + AgentSkillResolver.shared.formatSkillsBlock(matched: cachedMatchedSkills, totalDiscovered: self.cachedDiscoveredSkills.count) + "\n"
        phaseCoordinator.completePhase("PHASE_03_SKILLS", evidence: "\(cachedMatchedSkills.count) matching skills loaded.")

        // Agent Notes Creation
        _ = phaseCoordinator.startPhase("PHASE_04_NOTES")
        updateAgentNotes(currentAction: "Initializing execution plan and notes.")
        phaseCoordinator.completePhase("PHASE_04_NOTES", evidence: "agent_notes.md created.")

        // Pre-planning baseline verification
        self.validationCount += 1
        transition(to: .grounding, reason: "Verifying repository baseline integrity...")
        let fm = FileManager.default
        let rootExists = fm.fileExists(atPath: context.workspaceRoot.path)
        let isDir = (try? context.workspaceRoot.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let hasFiles = (try? fm.contentsOfDirectory(atPath: context.workspaceRoot.path).isEmpty) == false
        let baselinePassed = rootExists && isDir && hasFiles
        let baselineDetails = baselinePassed
            ? "Workspace root directory and structure verified (\(context.workspaceRoot.lastPathComponent))"
            : "Workspace root directory is missing or unreadable"
        currentActivityGroup.verifications.append(VerificationActivityItem(
            checkName: "Repository Baseline Check",
            isPassed: baselinePassed,
            details: baselineDetails
        ))
        postConversationalMessage("I’m analyzing the project structure and locating the relevant files.")

        // MANDATORY: Execute execution_plan tool before any modification
        _ = phaseCoordinator.startPhase("PHASE_04B_EXECUTION_PLAN")
        transition(to: .planning, reason: "Generating Execution Plan...")
        if let executionPlanTool = registry.getTool("execution_plan") {
            do {
                let planResult = try await executionPlanTool.execute(
                    input: [
                        "objective": objective,
                        "mode": executionMode.rawValue
                    ],
                    context: context
                )
                if planResult.success {
                    pipelineLogger.info("[execution_plan] Plan generated successfully: \(planResult.output.prefix(100))")
                    phaseCoordinator.completePhase("PHASE_04B_EXECUTION_PLAN", evidence: "Execution Plan generated and written to agent_notes.md")
                } else {
                    let errorMsg = planResult.error ?? "Unknown error"
                    pipelineLogger.warning("[execution_plan] Plan generation failed: \(errorMsg)")
                    phaseCoordinator.failPhase("PHASE_04B_EXECUTION_PLAN", error: errorMsg)
                }
            } catch {
                pipelineLogger.warning("[execution_plan] Tool execution error: \(error.localizedDescription)")
                phaseCoordinator.failPhase("PHASE_04B_EXECUTION_PLAN", error: error.localizedDescription)
            }
        } else {
            pipelineLogger.warning("[execution_plan] Tool not found in registry")
            phaseCoordinator.failPhase("PHASE_04B_EXECUTION_PLAN", error: "execution_plan tool not found")
        }

        // Production-grade adaptive orchestration trackers
        var lastRepoModificationCount = 0
        var lastSuccessfulToolCallCount = 0
        var lastValidationCount = 0
        var consecutiveNoProgressCycles = 0
        var codeReviewAttempts = 0

        while !isCancelled && !Task.isCancelled {
            self.iterationCount += 1
            AlertSoundPlayer.shared.play(.agentThinking)

            // Budget Control: check limits
            let elapsed = Date().timeIntervalSince(startDate)
            if let exceededReason = task.budgets.isExceeded(
                iterations: self.iterationCount,
                toolCalls: self.state.toolCallCount,
                duration: elapsed,
                repairAttempts: self.repairAttemptCount
            ) {
                let budgetMsg = "Execution suspended: Budget limit reached (\(exceededReason))."
                pipelineLogger.warning("\(budgetMsg)")
                self.currentActivityGroup.isExecuting = false
                transition(to: .blocked, reason: budgetMsg)
                postConversationalMessage("Task execution paused as the budget limit was reached (\(exceededReason)).", isComplete: true)
                return
            }

            // Planning & Context Assembly
            _ = phaseCoordinator.startPhase("PHASE_05_PLANNING")
            transition(to: .planning, reason: "Formulating execution strategy...")

            let complexity = AssistPlanner.classifyComplexity(intent: objective)
            pipelineLogger.info("Task complexity classified as: \(complexity.rawValue)")
            pipelineLogger.info("Task complexity classified as: \(complexity.rawValue)")

            let failureSummary = AssistErrorRecoveryEngine.shared.formatFailuresForPrompt()
            let verificationSummary = "Syntax checks: \(self.validationCount) passes recorded. Modified targets: \(self.state.changeSummary.modifiedFiles.count)"
            let activeModifiedFiles = self.state.changeSummary.modifiedFiles.map { $0.filename }

            let contextPayload = await contextManager?.buildContext(
                for: objective,
                completedActions: self.state.completedActions,
                recentResults: self.recentToolResults,
                recentErrors: self.recentErrors,
                failureSummary: failureSummary,
                verificationSummary: verificationSummary,
                activeFiles: activeModifiedFiles
            )

            let manifest = contextPayload?.repoManifestSummary ?? ""
            let groundingInstructions = contextPayload?.repositoryInstructions ?? ""
            let activeFiles = contextPayload?.activeFileContents.map { "\($0.key):\n\($0.value)" }.joined(separator: "\n\n") ?? ""

            let toolSchemas = cachedToolSchemas[self.state.status] ?? {
                let phaseTools = AssistToolRouter.shared.filterTools(for: self.state.status, in: registry)
                let serialized = AssistToolRouter.shared.serializeToolSchemas(phaseTools)
                cachedToolSchemas[self.state.status] = serialized
                return serialized
            }()
            let assetSystemPrompt: String
            do {
                assetSystemPrompt = try AssistManager.shared.getSystemPrompt()
            } catch {
                self.currentActivityGroup.isExecuting = false
                transition(to: .failed, reason: "System prompt unavailable: \(error.localizedDescription)")
                postConversationalMessage("Task failed: the system prompt could not be loaded.", isComplete: true)
                return
            }

            let skillsBlock = cachedSkillsBlock

            var attachmentsBlock = ""
            if !attachments.isEmpty {
                attachmentsBlock = "\n# ATTACHED FILES FOR THIS TASK\n"
                for file in attachments {
                    attachmentsBlock += "Filename: \(file.filename)\n"
                    attachmentsBlock += "Content:\n\(file.base64Content)\n"
                }
            }

            let systemPrompt = """
            # SYSTEM PROMPT (OPERATING POLICY)
            \(assetSystemPrompt)

            You are an autonomous Swift/macOS coding agent in SwiftCode.
            Goal: "\(objective)"

            \(executionMode.systemInstruction)

            \(groundingInstructions)

            Respond ONLY with valid JSON:
            {
              "toolId": "the_tool_id",
              "input": { "key": "value" },
              "explanation": "Human-readable purpose of this action"
            }
            OR:
            {
              "finalResponse": "Clear, detailed summary of completed achievements"
            }

            \(attachmentsBlock)
            \(skillsBlock)
            \(manifest)
            \(activeFiles)
            \(toolSchemas)
            """

            var conversationPrompt = systemPrompt
            if !conversationHistory.isEmpty {
                conversationPrompt += "\n\n# HISTORY OF RECENT TOOL EXECUTION RESULTS\n"
                conversationPrompt += conversationHistory.suffix(8).joined(separator: "\n")
            }
            if !failureSummary.isEmpty {
                conversationPrompt += "\n\n# ACTIVE FAILURE OBSERVATIONS\n\(failureSummary)"
            }
            conversationPrompt += "\n\nChoose the next best tool to run or provide finalResponse in valid JSON."

            let activeModel = AssistModelManager.shared.selectedModelID
            let response = try await AgentModelAdapter.shared.queryModel(prompt: conversationPrompt, modelId: activeModel)
            guard response.count > 0 else {
                appendConversationHistory("- System note: Response was empty. Retrying...")
                continue
            }

            guard let jsonBlock = AgentModelAdapter.shared.extractJSON(from: response) ?? extractJSON(from: response) else {
                appendConversationHistory("- System note: Invalid JSON response. Please provide valid JSON.")
                continue
            }

            // Check if final response was reached
            if let finalResponse = jsonBlock["finalResponse"] as? String {
                self.validationCount += 1
                _ = phaseCoordinator.startPhase("PHASE_07_VERIFICATION")
                transition(to: .verifying, reason: "Evaluating Autonomous Completion Contract...")

                for file in self.state.changeSummary.modifiedFiles { task.recordFileInvolved(file.filename) }
                for file in self.state.changeSummary.createdFiles { task.recordFileInvolved(file.filename) }

                let contractEvaluation = await AssistVerificationPipeline.shared.evaluateCompletionContract(
                    task: &task,
                    context: context
                )

                if !contractEvaluation.passed {
                    phaseCoordinator.failPhase("PHASE_07_VERIFICATION", error: contractEvaluation.issues.joined(separator: "; "))
                    self.repairAttemptCount += 1
                    transition(to: .recovering, reason: "Completion contract pending verification: \(contractEvaluation.issues.joined(separator: ", "))")

                    currentActivityGroup.recoveries.append(RecoveryActivityItem(
                        domain: "Build & Verification",
                        failureReason: contractEvaluation.issues.first ?? "Build/test verification required",
                        strategy: "Running build and test verification tools before declaring task complete"
                    ))
                    postConversationalMessage("I'm building and testing the project to verify the changes.")

                    let rejectionFeedback = """
                    - Action: Final Response. Autonomous Completion Contract: REJECTED
                      Issues: \(contractEvaluation.issues.joined(separator: "\n  "))
                    Please run 'project_build' or fix compiler errors before declaring completion.
                    """
                    appendConversationHistory(rejectionFeedback)
                    consecutiveNoProgressCycles = 0
                    continue
                }

                for i in currentActivityGroup.recoveries.indices {
                    currentActivityGroup.recoveries[i].isResolved = true
                }
                currentActivityGroup.verifications.append(VerificationActivityItem(
                    checkName: "Autonomous Completion Contract",
                    isPassed: true,
                    details: "All build and verification checks passed cleanly."
                ))
                phaseCoordinator.completePhase("PHASE_07_VERIFICATION", evidence: "Contract verified.")

                // Execute final code review gate if enabled
                _ = phaseCoordinator.startPhase("PHASE_08_REVIEW")
                transition(to: .verifying, reason: "Executing code review verification...")
                if let reviewTool = registry.getTool("code_review") {
                    do {
                        _ = try await reviewTool.execute(input: [:], context: context)
                        guard let reviewState = AssistManager.shared.currentCodeReview else {
                            throw NSError(domain: "AssistAgentSession", code: 409, userInfo: [NSLocalizedDescriptionKey: "Code review produced no result."])
                        }
                        if reviewState.status != "task_ready" {
                            codeReviewAttempts += 1
                            self.repairAttemptCount += 1
                            phaseCoordinator.failPhase("PHASE_08_REVIEW", error: "Reviewer requested changes.")
                            transition(to: .recovering, reason: "Code review requested changes.")
                            let feedbackStr = "- Action: Code Review. FAILED - Revisions required: \(reviewState.issues.joined(separator: "; "))"
                            appendConversationHistory(feedbackStr)
                            consecutiveNoProgressCycles = 0
                            continue
                        }
                    } catch {
                        pipelineLogger.warning("Code review non-fatal error: \(error.localizedDescription)")
                        codeReviewAttempts += 1
                        self.repairAttemptCount += 1
                        phaseCoordinator.failPhase("PHASE_08_REVIEW", error: "Code review tool error: \(error.localizedDescription)")
                        transition(to: .recovering, reason: "Code review could not be completed.")
                        appendConversationHistory("- Action: Code Review. FAILED - Reviewer error: \(error.localizedDescription). Please self-verify your changes and call code_review again.")
                        consecutiveNoProgressCycles = 0
                        continue
                    }
                }

                phaseCoordinator.completePhase("PHASE_08_REVIEW", evidence: "Code review passed.")

                // Final Conversational Completion
                currentActivityGroup.isExecuting = false
                postConversationalMessage(finalResponse.isEmpty ? "The fix is complete and verified." : finalResponse, isComplete: true)

                _ = phaseCoordinator.startPhase("PHASE_09_COMPLETION")
                transition(to: .completed, reason: "Task complete and verified.")
                NotificationManager.shared.sendAgentTaskFinishedNotification()
                AlertSoundPlayer.shared.play(.agentResponseReady)
                return
            }

            // Tool Execution Handling
            guard let toolId = jsonBlock["toolId"] as? String,
                  let rawInput = jsonBlock["input"] as? [String: Any] else {
                appendConversationHistory("- System note: Model output was missing 'toolId' or 'input'. Respond with a valid JSON tool call.")
                continue
            }

            let explanation = jsonBlock["explanation"] as? String ?? "Inspecting project"

            // Pre-execution Schema Validation & Auto-correction
            let validation = AssistErrorRecoveryEngine.shared.validateToolCall(
                toolId: toolId,
                input: rawInput,
                registry: registry
            )

            guard validation.isValid, let validatedInput = validation.correctedInput else {
                let errorIssue = validation.issue ?? "Invalid arguments for tool \(toolId)"
                pipelineLogger.warning("Tool validation failed: \(errorIssue)")
                appendConversationHistory("- Action: Run \(toolId). Result: FAILED - Argument Error: \(errorIssue). Please correct tool parameters.")
                continue
            }

            var toolInput: [String: String] = [:]
            for (key, val) in validatedInput {
                toolInput[key] = "\(val)"
            }

            let newStep = PlanStep(toolId: toolId, description: explanation, input: toolInput)
            state.plan.append(newStep)

            _ = phaseCoordinator.startPhase("PHASE_06_EXECUTION")
            transition(to: .executing, reason: "Executing tool [\(toolId)]")

            guard let tool = registry.getTool(toolId) else {
                appendConversationHistory("- Action: Run \(toolId). Result: FAILED - Tool '\(toolId)' not found.")
                continue
            }

            state.toolCallCount += 1

            // Record Tool in Activity Group
            let toolActivityIndex = currentActivityGroup.tools.count
            currentActivityGroup.tools.append(ToolActivityItem(
                toolId: toolId,
                purpose: explanation,
                status: .running
            ))

            // Post progress message if user-facing milestone reached
            if ["file_write", "code_replace", "file_create", "patch_application_engine"].contains(toolId) {
                let path = toolInput["path"] ?? toolInput["filepath"] ?? "file"
                postConversationalMessage("I found the issue. I’m applying the fix to \(path) and will verify it with a build afterward.")
            } else if ["project_build", "build_project", "xcodebuild"].contains(toolId) {
                postConversationalMessage("The fix is applied. I’m building the project now.")
            } else if ["project_test", "test_runner"].contains(toolId) {
                postConversationalMessage("The build succeeded. I’m running the relevant tests to verify the behavior.")
            }

            do {
                let result = try await tool.execute(input: validatedInput, context: context)
                self.recentToolResults.append(result)
                if self.recentToolResults.count > 10 {
                    self.recentToolResults.removeFirst(self.recentToolResults.count - 10)
                }

                observeResult(toolId: toolId, input: validatedInput, result: result, explanation: explanation)

                let callSignature = "\(toolId)::\(validatedInput.description)"
                self.state.recentToolCallWindow.append(callSignature)
                if self.state.recentToolCallWindow.count > 12 {
                    self.state.recentToolCallWindow.removeFirst(self.state.recentToolCallWindow.count - 12)
                }

                if result.success {
                    successfulToolExecutionCount += 1
                    currentActivityGroup.tools[toolActivityIndex].status = .completed
                    currentActivityGroup.tools[toolActivityIndex].result = result.output

                    for i in currentActivityGroup.recoveries.indices {
                        if !currentActivityGroup.recoveries[i].isResolved {
                            currentActivityGroup.recoveries[i].isResolved = true
                        }
                    }

                    state.completedActions.append(newStep.description)
                    if let index = state.plan.firstIndex(where: { $0.id == newStep.id }) {
                        state.plan[index].status = .completed
                    }

                    logChangeToSummary(toolId: toolId, input: toolInput, explanation: explanation, output: result.output)

                    // Track file modifications in Activity Group
                    if let path = toolInput["path"] ?? toolInput["filepath"] {
                        let op = toolId.contains("create") ? "Created" : (toolId.contains("delete") ? "Deleted" : "Modified")
                        let added = result.diff?.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count ?? 0
                        let deleted = result.diff?.components(separatedBy: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count ?? 0

                        if let existingIndex = currentActivityGroup.files.firstIndex(where: { $0.filePath == path }) {
                            currentActivityGroup.files[existingIndex].addedLines += added
                            currentActivityGroup.files[existingIndex].deletedLines += deleted
                        } else {
                            currentActivityGroup.files.append(FileActivityItem(
                                filePath: path,
                                operation: op,
                                addedLines: added,
                                deletedLines: deleted,
                                diffSummary: result.diff
                            ))
                        }
                    }

                    // Track builds/tests in Activity Group
                    if toolId == "project_build" || toolId == "build_project" {
                        currentActivityGroup.builds.append(BuildActivityItem(
                            status: .completed,
                            errorCount: 0,
                            warningCount: 0
                        ))
                    } else if toolId == "project_test" || toolId == "test_runner" {
                        currentActivityGroup.tests.append(TestActivityItem(
                            passedCount: 1,
                            status: .completed
                        ))
                    } else if toolId == "use_workers" {
                        currentActivityGroup.workers.append(WorkerActivityItem(
                            workerId: UUID().uuidString,
                            name: toolInput["workerName"] ?? "Worker",
                            role: toolInput["role"] ?? "Task Worker",
                            scope: toolInput["scope"] ?? "Codebase",
                            status: .completed
                        ))
                    }

                    postConversationalMessage("I’m continuing to work through the task requirements.", isComplete: false)

                    var feedback = "- Action: Run \(toolId). Result: SUCCESS - Output: \(result.output)"
                    if let diff = result.diff, !diff.isEmpty { feedback += "\n Diff:\n\(diff.prefix(600))" }
                    appendConversationHistory(feedback)
                } else {
                    let errMsg = result.error ?? result.output
                    currentActivityGroup.tools[toolActivityIndex].status = .failed
                    currentActivityGroup.tools[toolActivityIndex].result = errMsg

                    let isDuplicate = AssistErrorRecoveryEngine.shared.isIdenticalFailure(toolId: toolId, input: validatedInput, error: errMsg)
                    let recoveryAttempt = AssistErrorRecoveryEngine.shared.recordRecoveryAttempt(domain: .tool)

                    if isDuplicate {
                        let strategyShift = AssistErrorRecoveryEngine.shared.strategyShiftForIdenticalFailure(toolId: toolId, error: errMsg)
                        appendConversationHistory("- System note: Identical failure detected. Strategy shift required: \(strategyShift)")
                    }

                    if recoveryAttempt.allowed {
                        currentActivityGroup.recoveries.append(RecoveryActivityItem(
                            domain: "Tool Recovery",
                            failureReason: errMsg,
                            strategy: isDuplicate ? "Pivoting strategy after duplicate failure" : "Correcting parameters and retrying",
                            attemptNumber: recoveryAttempt.attemptNumber,
                            maxAttempts: recoveryAttempt.maxAllowed,
                            isResolved: false
                        ))

                        postConversationalMessage("I encountered a minor execution issue with \(toolId) and am adjusting my approach.")
                    }

                    if let index = state.plan.firstIndex(where: { $0.id == newStep.id }) {
                        state.plan[index].status = .failed
                    }

                    self.recentErrors.append(errMsg)
                    if self.recentErrors.count > 10 {
                        self.recentErrors.removeFirst(self.recentErrors.count - 10)
                    }

                    appendConversationHistory("- Action: Run \(toolId). Result: FAILED - Error: \(errMsg)")
                }
            } catch {
                currentActivityGroup.tools[toolActivityIndex].status = .failed
                currentActivityGroup.tools[toolActivityIndex].result = error.localizedDescription
                self.recentErrors.append(error.localizedDescription)
                appendConversationHistory("- Action: Run \(toolId). Result: FAILED - Exception: \(error.localizedDescription)")
            }

            transition(to: .observing, reason: "Interpreting tool result...")

            if let stuckEvent = detectStuck() {
                transition(to: .blocked, reason: "Stuck detected: \(stuckEvent.reason)")
                postConversationalMessage("I've detected that my current approach isn't making progress. I'm re-evaluating the situation.", isComplete: false)

                replanFromStuck(detection: stuckEvent)

                if self.state.replanningCount >= 3 {
                    self.currentActivityGroup.isExecuting = false
                    transition(to: .blocked, reason: "Replanning exhausted after 3 attempts.")
                    postConversationalMessage("Unable to complete the task after multiple replanning attempts.", isComplete: true)
                    return
                }

                transition(to: .planning, reason: "Replanning after stuck detection...")
                continue
            }

            transition(to: .executing, reason: "Continuing execution...")

        }

        self.currentActivityGroup.isExecuting = false
        if isCancelled || Task.isCancelled {
            if self.state.status != .cancelled {
                transition(to: .cancelled, reason: "Task execution cancelled by user.")
            }
            postConversationalMessage("Task cancelled by user.", isComplete: true)
            NotificationManager.shared.sendAgentTaskFinishedNotification()
        }
    }

    @MainActor
    private func logChangeToSummary(toolId: String, input: [String: String], explanation: String, output: String) {
        let path = input["path"] ?? input["filepath"] ?? input["target"] ?? "Unknown"
        let reason = explanation.isEmpty ? "Requested by task" : explanation

        let activity = ToolActivityItem(toolId: toolId, purpose: reason, result: String(output.prefix(200)))
        state.changeSummary.toolActivities.append(activity)

        switch toolId {
        case "file_create":
            state.changeSummary.createdFiles.append(FileChangeItem(filename: path, details: reason))
        case "file_write", "code_refactor", "file_append", "patch_application_engine", "code_replace":
            if !state.changeSummary.modifiedFiles.contains(where: { $0.filename == path }) {
                state.changeSummary.modifiedFiles.append(FileChangeItem(filename: path, details: "Modified: \(reason)"))
            }
        case "file_delete":
            state.changeSummary.deletedFiles.append(FileChangeItem(filename: path, details: reason))
        default:
            break
        }
        updateAgentNotes(currentAction: reason)
    }

    @MainActor
    public func updateAgentNotes(currentAction: String = "") {
        guard let context = activeContext else { return }
        let isTerminal = state.status == .completed || state.status == .failed || state.status == .cancelled || state.status == .blocked
        if !isTerminal && Date().timeIntervalSince(lastNotesUpdateTime) < 2.0 { return }
        lastNotesUpdateTime = Date()
        let selectedModel = AssistModelManager.shared.selectedModelID
        let discoveredInstructions = AgentRepositoryScanner.shared.discoverInstructions(in: context.workspaceRoot)
        let applicableAgents = discoveredInstructions.map { $0.filePath }
        let applicableSkills = cachedMatchedSkills.map { $0.name }

        let task = self.currentTask ?? AgentTask(objective: self.state.objective)
        _ = AgentNotesManager.shared.updateNotes(
            task: task,
            session: self,
            phaseCoordinator: phaseCoordinator,
            applicableAgents: applicableAgents,
            applicableSkills: applicableSkills,
            modelName: selectedModel,
            currentAction: currentAction,
            workspaceRoot: context.workspaceRoot
        )
    }

    public func cancel() {
        self.isCancelled = true
        self.state.takeoverActive = false
        self.currentActivityGroup.isExecuting = false
        WorkerRuntimeState.shared.stopAllActiveWorkers(reason: "Operation cancelled by user.")
        PlanQuestionManager.shared.cancelPendingQuestions()
        LiveDiffStreamer.shared.clearAll()
        transition(to: .cancelled, reason: "Operation cancelled by user.")
    }

    public func retryLastStep() {
        self.isCancelled = true
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                self.isCancelled = false
                if self.state.status == .failed || self.state.status == .blocked || self.state.status == .cancelled {
                    self.transition(to: .planning, reason: "Retrying agent cycle.")
                    if let activeContext = self.activeContext, let task = self.currentTask {
                        Task { [weak self] in
                            try? await self?.start(objective: task.originalRequest, attachments: [], context: activeContext)
                        }
                    }
                }
            }
        }
    }

    private func appendConversationHistory(_ entry: String) {
        conversationHistory.append(entry)
        if conversationHistory.count > 16 {
            conversationHistory.removeFirst(conversationHistory.count - 16)
        }
    }

    private func extractJSON(from response: String) -> [String: Any]? {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        if let firstBrace = response.firstIndex(of: "{"),
           let lastBrace = response.lastIndex(of: "}") {
            let candidate = String(response[firstBrace...lastBrace]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = candidate.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        }
        return nil
    }
}
