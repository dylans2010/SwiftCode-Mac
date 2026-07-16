import Foundation

/// [CRITICAL SYSTEM FILE] - HIGH RISK
/// Master controller for fully autonomous execution - runs indefinitely with zero human interaction when takeover is enabled.
/// Integrates all autonomous systems: goal expansion, decision making, self-correction, validation, and stability regulation.
@MainActor
public final class _AssistCriticalAutonomousEngine {
    private let context: AssistContext

    // Core Components
    private let orchestrator: _AssistCriticalTaskOrchestrator
    private let validator: _AssistCriticalValidationEngine
    private let analyzer: _AssistCriticalCodebaseAnalyzer

    // New Autonomous Systems
    private let goalExpansion: AssistGoalExpansionEngine
    private let taskContinuation: AssistTaskContinuationEngine
    private let decisionEngine: AssistAutonomousDecisionEngine
    private let progressEvaluator: AssistProgressEvaluator
    private let riskAssessment: AssistRiskAssessmentEngine
    private let rootCauseAnalyzer: AssistFailureRootCauseAnalyzer
    private let recoveryGenerator: AssistRecoveryStrategyGenerator
    private let outputVerifier: AssistOutputVerificationEngine
    private let integrityScanner: AssistCodeIntegrityScanner
    private let contextPersistence: AssistExecutionContextPersistenceStore
    private let driftDetector: AssistContextDriftDetector
    private let memoryValidator: AssistMemoryConsistencyValidator
    private let stabilityRegulator: AssistLoopStabilityRegulator
    private let behaviorMonitor: AssistRuntimeBehaviorMonitor
    private let traceEngine: AssistExecutionTraceEngine
    private let performanceProfiling: AssistPerformanceProfilingEngine
    private let resourceMonitor: AssistResourceUsageMonitor
    private let optimizationEngine: AssistOptimizationEngine

    // State Management
    private var isRunning = false
    private var iterationCount = 0
    private var previousValidationFeedbacks: [String] = []
    private var completedTasks: [String] = []
    private var expandedGoals: [String] = []

    public init(context: AssistContext) {
        self.context = context

        // Initialize core components
        self.orchestrator = _AssistCriticalTaskOrchestrator(context: context)
        self.validator = _AssistCriticalValidationEngine(context: context)
        self.analyzer = _AssistCriticalCodebaseAnalyzer(context: context)

        // Initialize new autonomous systems
        self.goalExpansion = AssistGoalExpansionEngine(context: context)
        self.taskContinuation = AssistTaskContinuationEngine(context: context)
        self.decisionEngine = AssistAutonomousDecisionEngine(context: context)
        self.progressEvaluator = AssistProgressEvaluator(context: context)
        self.riskAssessment = AssistRiskAssessmentEngine(context: context)
        self.rootCauseAnalyzer = AssistFailureRootCauseAnalyzer(context: context)
        self.recoveryGenerator = AssistRecoveryStrategyGenerator(context: context)
        self.outputVerifier = AssistOutputVerificationEngine(context: context)
        self.integrityScanner = AssistCodeIntegrityScanner(context: context)
        self.contextPersistence = AssistExecutionContextPersistenceStore(context: context)
        self.driftDetector = AssistContextDriftDetector(context: context)
        self.memoryValidator = AssistMemoryConsistencyValidator(context: context)
        self.stabilityRegulator = AssistLoopStabilityRegulator(context: context)
        self.behaviorMonitor = AssistRuntimeBehaviorMonitor(context: context)
        self.traceEngine = AssistExecutionTraceEngine(context: context)
        self.performanceProfiling = AssistPerformanceProfilingEngine(context: context)
        self.resourceMonitor = AssistResourceUsageMonitor(context: context)
        self.optimizationEngine = AssistOptimizationEngine(context: context)
    }

    /// Starts the fully autonomous execution loop - runs indefinitely when takeover is enabled
    public func run(intent: String) async throws {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        await context.logger.info("🚀 Starting FULLY AUTONOMOUS ENGINE for: \(intent)", toolId: "AutonomousEngine")

        // Initialize monitoring and tracing
        behaviorMonitor.startMonitoring()
        resourceMonitor.startMonitoring()

        // Phase 0: Initial Analysis
        let summary = try await analyzer.analyze()
        await context.logger.info("✅ Initial codebase analysis: \(summary.swiftFileCount) Swift files", toolId: "AutonomousEngine")

        let originalIntent = intent
        iterationCount = 0
        var currentIntent = intent
        var taskCount = 0

        let takeoverEnabled = UserDefaults.standard.bool(forKey: "assist.takeoverEnabled")

        // CORE AUTONOMOUS LOOP - Runs indefinitely when takeover is enabled
        while true {
            iterationCount += 1
            traceEngine.recordEvent(iteration: iterationCount, type: .iterationStart, description: "Starting iteration \(iterationCount) for: \(currentIntent)")

            await context.logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", toolId: "AutonomousEngine")
            await context.logger.info("🔄 ITERATION \(iterationCount) - Task #\(taskCount + 1)", toolId: "AutonomousEngine")
            await context.logger.info("📋 Goal: \(currentIntent)", toolId: "AutonomousEngine")

            // PHASE 1: Analyze Current State
            let startTime = Date()

            // Check memory consistency
            let memoryCheck = await memoryValidator.validateConsistency()
            if !memoryCheck.isConsistent {
                await context.logger.warning("⚠️ Memory consistency issues: \(memoryCheck.issues.joined(separator: ", "))", toolId: "AutonomousEngine")
            }

            // Check for context drift
            let driftAnalysis = await driftDetector.detectDrift(
                originalGoal: originalIntent,
                currentGoal: currentIntent,
                completedTasks: completedTasks
            )
            if driftAnalysis.hasDrift {
                await context.logger.warning("⚠️ Context drift detected: \(driftAnalysis.reason)", toolId: "AutonomousEngine")
                // Reset to original intent if severe drift
                if driftAnalysis.driftScore > 0.8 {
                    currentIntent = originalIntent
                    await context.logger.info("↩️ Resetting to original intent due to severe drift", toolId: "AutonomousEngine")
                }
            }

            // PHASE 2: Generate Plan
            traceEngine.recordEvent(iteration: iterationCount, type: .planGenerated, description: "Generating plan")
            var plan = try await orchestrator.createPlan(for: currentIntent)
            await context.logger.info("📝 Plan generated: \(plan.steps.count) steps", toolId: "AutonomousEngine")

            // PHASE 3: Assess Risk
            let riskResult = await riskAssessment.assessRisk(plan: plan)
            await context.logger.info("🛡️ Risk assessment: \(riskResult.level)", toolId: "AutonomousEngine")

            if !riskResult.shouldProceed {
                await context.logger.error("🚫 High risk operation detected - skipping for safety", toolId: "AutonomousEngine")
                await triggerTakeover(reason: "High risk operation: \(riskResult.concerns.joined(separator: ", "))")
                break
            }

            // PHASE 4: Optimize Plan
            let optimization = await optimizationEngine.optimizePlan(plan)
            if optimization.wasOptimized, let optimizedPlan = optimization.optimizedPlan {
                plan = optimizedPlan
                await context.logger.info("⚡ Plan optimized: \(optimization.improvements.joined(separator: ", "))", toolId: "AutonomousEngine")
            }

            // PHASE 5: Execute Plan
            traceEngine.recordEvent(iteration: iterationCount, type: .executionStarted, description: "Executing plan")
            try await orchestrator.execute(plan: &plan)

            let executionTime = Date().timeIntervalSince(startTime)
            performanceProfiling.recordOperation(
                type: "PlanExecution",
                startTime: startTime,
                endTime: Date(),
                success: plan.status == .completed
            )

            await context.logger.info("✅ Execution completed in \(String(format: "%.2f", executionTime))s", toolId: "AutonomousEngine")

            // PHASE 6: Verify Output
            let outputVerification = await outputVerifier.verify(plan: plan)
            if !outputVerification.isComplete {
                await context.logger.warning("⚠️ Output verification failed: \(outputVerification.issues.joined(separator: ", "))", toolId: "AutonomousEngine")
            }

            // PHASE 7: Scan Code Integrity
            let integrityReports = await integrityScanner.scanPlan(plan: plan)
            for (path, report) in integrityReports where report.hasIssues {
                await context.logger.warning("⚠️ Integrity issues in \(path): \(report.syntaxErrors.count) syntax, \(report.structuralIssues.count) structural", toolId: "AutonomousEngine")
            }

            // PHASE 8: Validate Results
            traceEngine.recordEvent(iteration: iterationCount, type: .validationPerformed, description: "Validating results")
            let validationResult = try await validator.validate(plan: plan)

            // Record progress
            progressEvaluator.recordProgress(
                iteration: iterationCount,
                goal: currentIntent,
                plan: plan,
                validationResult: validationResult
            )

            // Record stability data
            stabilityRegulator.recordExecution(
                iteration: iterationCount,
                goal: currentIntent,
                plan: plan,
                validationResult: validationResult
            )

            if validationResult.isSuccess {
                // SUCCESS PATH
                await context.logger.info("✅ Task completed successfully after \(iterationCount) iterations!", toolId: "AutonomousEngine")
                completedTasks.append(currentIntent)
                taskCount += 1

                traceEngine.recordEvent(iteration: iterationCount, type: .iterationEnd, description: "Task completed successfully")

                // PHASE 9: Continuous Build Validation (if needed)
                // TODO: Integrate compiler diagnostics here

                // PHASE 10: Self-Improvement
                // TODO: Run autonomous review and optimization

                // PHASE 11: Goal Expansion
                if takeoverEnabled {
                    await context.logger.info("🎯 Expanding goals for continuous execution...", toolId: "AutonomousEngine")
                    traceEngine.recordEvent(iteration: iterationCount, type: .goalExpanded, description: "Expanding goals")

                    let newGoals = await goalExpansion.expandGoals(originalGoal: currentIntent, completedPlan: plan)
                    expandedGoals.append(contentsOf: newGoals)

                    if !newGoals.isEmpty {
                        await context.logger.info("📈 Generated \(newGoals.count) follow-up goals", toolId: "AutonomousEngine")
                    }

                    // PHASE 12: Task Continuation Decision
                    let shouldContinue = await taskContinuation.shouldContinue(
                        currentGoal: currentIntent,
                        completedPlan: plan
                    )

                    if shouldContinue, let nextTask = await taskContinuation.generateNextTask(
                        previousGoal: currentIntent,
                        completedPlan: plan,
                        expandedGoals: expandedGoals
                    ) {
                        // Continue with next expanded goal
                        currentIntent = nextTask
                        expandedGoals.removeFirst() // Remove used goal
                        iterationCount = 0 // Reset iteration counter for new task
                        previousValidationFeedbacks.removeAll()

                        // Persist context
                        await contextPersistence.saveContext(
                            goal: originalIntent,
                            completedTasks: completedTasks,
                            expandedGoals: expandedGoals,
                            iteration: taskCount,
                            stepsExecuted: plan.steps.count
                        )

                        await context.logger.info("➡️ Continuing autonomously to next task: \(nextTask)", toolId: "AutonomousEngine")

                        // Update metrics and continue loop
                        resourceMonitor.updateMetrics()
                        behaviorMonitor.recordMemorySnapshot()
                        continue
                    } else {
                        // No more tasks or continuation limit reached
                        await context.logger.info("🏁 Autonomous execution complete. Processed \(taskCount) tasks.", toolId: "AutonomousEngine")
                        await performanceProfiling.logSummary()
                        await resourceMonitor.logResourceSummary()
                        break
                    }
                } else {
                    // Takeover not enabled - stop after one task
                    await context.logger.info("🏁 Task complete. Takeover not enabled, stopping.", toolId: "AutonomousEngine")
                    break
                }
            } else {
                // FAILURE PATH - Apply intelligent decision making and recovery
                await context.logger.warning("❌ Validation failed: \(validationResult.feedback)", toolId: "AutonomousEngine")
                previousValidationFeedbacks.append(validationResult.feedback)

                // PHASE 13: Stability Detection
                let stabilityIssue = await stabilityRegulator.detectStabilityIssues()
                switch stabilityIssue {
                case .infiniteLoop(let reason):
                    await triggerTakeover(reason: "Infinite loop: \(reason)")
                    throw AutonomousError.infiniteLoopDetected

                case .oscillation(let pattern):
                    await triggerTakeover(reason: "Oscillation: \(pattern)")
                    throw AutonomousError.oscillationDetected

                case .noProgress(let iterations):
                    await triggerTakeover(reason: "No progress after \(iterations) iterations")
                    throw AutonomousError.noProgressCycle

                case .repetitiveActions:
                    await context.logger.warning("⚠️ Repetitive actions detected - adjusting strategy", toolId: "AutonomousEngine")
                    // Try to break the pattern by altering the approach
                    currentIntent = "Take a different approach: \(currentIntent)"

                case .none:
                    break
                }

                // Check if progress is being made overall
                if !progressEvaluator.isProgressBeingMade() {
                    await context.logger.error("⛔ No meaningful progress detected", toolId: "AutonomousEngine")
                    await triggerTakeover(reason: "No meaningful progress after multiple attempts")
                    throw AutonomousError.noProgressCycle
                }

                // PHASE 14: Decision Engine
                traceEngine.recordEvent(iteration: iterationCount, type: .decisionMade, description: "Making autonomous decision")
                let decision = await decisionEngine.decide(
                    plan: plan,
                    validationResult: validationResult,
                    iterationCount: iterationCount,
                    previousFeedbacks: previousValidationFeedbacks
                )

                switch decision {
                case .continueExecution:
                    await context.logger.info("➡️ Decision: Continue execution", toolId: "AutonomousEngine")

                case .retryStep(let stepIndex):
                    await context.logger.info("🔄 Decision: Retry step \(stepIndex)", toolId: "AutonomousEngine")
                    // TODO: Implement single-step retry logic
                    currentIntent = "Retry step \(stepIndex): \(validationResult.feedback). Original: \(currentIntent)"

                case .replanTask(let feedback):
                    await context.logger.info("📋 Decision: Replan with feedback", toolId: "AutonomousEngine")
                    currentIntent = "Previous attempt failed. Feedback: \(feedback). Original goal: \(originalIntent)"

                case .optimizeOutput:
                    await context.logger.info("⚡ Decision: Optimize output", toolId: "AutonomousEngine")
                    // Run optimization and retry

                case .triggerTakeover(let reason):
                    await triggerTakeover(reason: reason)
                    throw AutonomousError.decisionEngineEscalation
                }

                // PHASE 15: Self-Correction via Root Cause Analysis
                let failedSteps = plan.steps.filter { $0.status == .failed }
                for failedStep in failedSteps {
                    let rootCause = await rootCauseAnalyzer.analyze(step: failedStep)
                    await context.logger.info("🔍 Root cause: \(rootCause.primaryCause)", toolId: "AutonomousEngine")

                    let recoveryStrategy = await recoveryGenerator.generateStrategy(
                        rootCause: rootCause,
                        failedStep: failedStep
                    )
                    await context.logger.info("🔧 Recovery: \(recoveryStrategy.approach) (success: \(Int(recoveryStrategy.estimatedSuccess * 100))%)", toolId: "AutonomousEngine")
                }

                // Check resource health
                let resourceHealthy = await resourceMonitor.isResourceUsageHealthy()
                if !resourceHealthy {
                    await triggerTakeover(reason: "Resource usage exceeded safe limits")
                    throw AutonomousError.resourceExhaustion
                }

                let behaviorHealthy = await behaviorMonitor.isHealthy()
                if !behaviorHealthy {
                    await triggerTakeover(reason: "Unhealthy runtime behavior detected")
                    throw AutonomousError.unhealthyBehavior
                }

                // Safety check: enforce iteration limit per task (even with takeover)
                if iterationCount >= 20 {
                    await context.logger.error("⛔ Maximum iterations per task reached", toolId: "AutonomousEngine")
                    await triggerTakeover(reason: "Maximum iterations (\(iterationCount)) reached for current task without success")
                    throw AutonomousError.maxIterationsReached
                }
            }
        }

        // Final summary
        await context.logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", toolId: "AutonomousEngine")
        await context.logger.info("🎉 AUTONOMOUS EXECUTION SUMMARY", toolId: "AutonomousEngine")
        await context.logger.info("Tasks completed: \(completedTasks.count)", toolId: "AutonomousEngine")
        await context.logger.info("Total iterations: \(iterationCount)", toolId: "AutonomousEngine")
        await context.logger.info(progressEvaluator.getSummary(), toolId: "AutonomousEngine")

        // Export trace for debugging
        let trace = traceEngine.exportTrace()
        await context.logger.info("Execution trace exported (\(trace.count) chars)", toolId: "AutonomousEngine")
    }

    private func triggerTakeover(reason: String) async {
        await MainActor.run {
            AssistManager.shared.takeoverReason = reason
            // UI will show takeover overlay
        }
        await context.logger.error("🛑 TAKEOVER TRIGGERED: \(reason)", toolId: "AutonomousEngine")
    }

    public enum AutonomousError: Error {
        case maxIterationsReached
        case infiniteLoopDetected
        case oscillationDetected
        case noProgressCycle
        case decisionEngineEscalation
        case resourceExhaustion
        case unhealthyBehavior
    }
}
