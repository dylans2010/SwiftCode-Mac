import Foundation

@MainActor
public final class _AssistCriticalAutonomousEngine {
    private let context: AssistContext

    private let orchestrator: _AssistCriticalTaskOrchestrator
    private let validator: _AssistCriticalValidationEngine
    private let analyzer: _AssistCriticalCodebaseAnalyzer

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

    private var isRunning = false
    private var iterationCount = 0
    private var previousValidationFeedbacks: [String] = []
    private var completedTasks: [String] = []
    private var expandedGoals: [String] = []

    public init(context: AssistContext) {
        self.context = context

        self.orchestrator = _AssistCriticalTaskOrchestrator(context: context)
        self.validator = _AssistCriticalValidationEngine(context: context)
        self.analyzer = _AssistCriticalCodebaseAnalyzer(context: context)

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

    public func run(intent: String) async throws {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        await context.logger.info("🚀 Starting FULLY AUTONOMOUS ENGINE for: \(intent)", toolId: "AutonomousEngine")

        behaviorMonitor.startMonitoring()
        resourceMonitor.startMonitoring()

        let summary = try await analyzer.analyze()
        await context.logger.info("✅ Initial codebase analysis: \(summary.swiftFileCount) Swift files", toolId: "AutonomousEngine")

        let originalIntent = intent
        iterationCount = 0
        var currentIntent = intent
        var taskCount = 0

        let takeoverEnabled = UserDefaults.standard.bool(forKey: "assist.takeoverEnabled")

        while true {
            iterationCount += 1
            traceEngine.recordEvent(iteration: iterationCount, type: .iterationStart, description: "Starting iteration \(iterationCount) for: \(currentIntent)")

            await context.logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", toolId: "AutonomousEngine")
            await context.logger.info("🔄 ITERATION \(iterationCount) - Task #\(taskCount + 1)", toolId: "AutonomousEngine")
            await context.logger.info("📋 Goal: \(currentIntent)", toolId: "AutonomousEngine")

            let startTime = Date()

            let memoryCheck = await memoryValidator.validateConsistency()
            if !memoryCheck.isConsistent {
                await context.logger.warning("⚠️ Memory consistency issues: \(memoryCheck.issues.joined(separator: ", "))", toolId: "AutonomousEngine")
            }

            let driftAnalysis = await driftDetector.detectDrift(
                originalGoal: originalIntent,
                currentGoal: currentIntent,
                completedTasks: completedTasks
            )
            if driftAnalysis.hasDrift {
                await context.logger.warning("⚠️ Context drift detected: \(driftAnalysis.reason)", toolId: "AutonomousEngine")
                if driftAnalysis.driftScore > 0.8 {
                    currentIntent = originalIntent
                    await context.logger.info("↩️ Resetting to original intent due to severe drift", toolId: "AutonomousEngine")
                }
            }

            traceEngine.recordEvent(iteration: iterationCount, type: .planGenerated, description: "Generating plan")
            var plan = try await orchestrator.createPlan(for: currentIntent)
            await context.logger.info("📝 Plan generated: \(plan.steps.count) steps", toolId: "AutonomousEngine")

            let riskResult = await riskAssessment.assessRisk(plan: plan)
            await context.logger.info("🛡️ Risk assessment: \(riskResult.level)", toolId: "AutonomousEngine")

            if !riskResult.shouldProceed {
                await context.logger.error("🚫 High risk operation detected - skipping for safety", toolId: "AutonomousEngine")
                await triggerTakeover(reason: "High risk operation: \(riskResult.concerns.joined(separator: ", "))")
                break
            }

            let optimization = await optimizationEngine.optimizePlan(plan)
            if optimization.wasOptimized, let optimizedPlan = optimization.optimizedPlan {
                plan = optimizedPlan
                await context.logger.info("⚡ Plan optimized: \(optimization.improvements.joined(separator: ", "))", toolId: "AutonomousEngine")
            }

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

            let outputVerification = await outputVerifier.verify(plan: plan)
            if !outputVerification.isComplete {
                await context.logger.warning("⚠️ Output verification failed: \(outputVerification.issues.joined(separator: ", "))", toolId: "AutonomousEngine")
            }

            let integrityReports = await integrityScanner.scanPlan(plan: plan)
            for (path, report) in integrityReports where report.hasIssues {
                await context.logger.warning("⚠️ Integrity issues in \(path): \(report.syntaxErrors.count) syntax, \(report.structuralIssues.count) structural", toolId: "AutonomousEngine")
            }

            traceEngine.recordEvent(iteration: iterationCount, type: .validationPerformed, description: "Validating results")
            let validationResult = try await validator.validate(plan: plan)

            progressEvaluator.recordProgress(
                iteration: iterationCount,
                goal: currentIntent,
                plan: plan,
                validationResult: validationResult
            )

            stabilityRegulator.recordExecution(
                iteration: iterationCount,
                goal: currentIntent,
                plan: plan,
                validationResult: validationResult
            )

            if validationResult.isSuccess {
                await context.logger.info("✅ Task completed successfully after \(iterationCount) iterations!", toolId: "AutonomousEngine")
                completedTasks.append(currentIntent)
                taskCount += 1

                traceEngine.recordEvent(iteration: iterationCount, type: .iterationEnd, description: "Task completed successfully")

                if takeoverEnabled {
                    await context.logger.info("🎯 Expanding goals for continuous execution...", toolId: "AutonomousEngine")
                    traceEngine.recordEvent(iteration: iterationCount, type: .goalExpanded, description: "Expanding goals")

                    let newGoals = await goalExpansion.expandGoals(originalGoal: currentIntent, completedPlan: plan)
                    expandedGoals.append(contentsOf: newGoals)

                    if !newGoals.isEmpty {
                        await context.logger.info("📈 Generated \(newGoals.count) follow-up goals", toolId: "AutonomousEngine")
                    }

                    let shouldContinue = await taskContinuation.shouldContinue(
                        currentGoal: currentIntent,
                        completedPlan: plan
                    )

                    if shouldContinue, let nextTask = await taskContinuation.generateNextTask(
                        previousGoal: currentIntent,
                        completedPlan: plan,
                        expandedGoals: expandedGoals
                    ) {
                        currentIntent = nextTask
                        expandedGoals.removeFirst()
                        iterationCount = 0
                        previousValidationFeedbacks.removeAll()

                        await contextPersistence.saveContext(
                            goal: originalIntent,
                            completedTasks: completedTasks,
                            expandedGoals: expandedGoals,
                            iteration: taskCount,
                            stepsExecuted: plan.steps.count
                        )

                        await context.logger.info("➡️ Continuing autonomously to next task: \(nextTask)", toolId: "AutonomousEngine")

                        resourceMonitor.updateMetrics()
                        behaviorMonitor.recordMemorySnapshot()
                        continue
                    } else {
                        await context.logger.info("🏁 Autonomous execution complete. Processed \(taskCount) tasks.", toolId: "AutonomousEngine")
                        await performanceProfiling.logSummary()
                        await resourceMonitor.logResourceSummary()
                        break
                    }
                } else {
                    await context.logger.info("🏁 Task complete. Takeover not enabled, stopping.", toolId: "AutonomousEngine")
                    break
                }
            } else {
                await context.logger.warning("❌ Validation failed: \(validationResult.feedback)", toolId: "AutonomousEngine")
                previousValidationFeedbacks.append(validationResult.feedback)

                let stabilityIssue = await stabilityRegulator.detectStabilityIssues()
                switch stabilityIssue {
                case .infiniteLoop(let reason):
                    await context.logger.warning("⚠️ Potential infinite loop detected: \(reason). Attempting to break the loop by adjusting strategy.", toolId: "AutonomousEngine")
                    currentIntent = "Break out of loop/stagnation. Try a completely different technique for: \(currentIntent)"
                case .oscillation(let pattern):
                    await context.logger.warning("⚠️ Potential oscillation detected: \(pattern). Attempting to break the cycle by adjusting strategy.", toolId: "AutonomousEngine")
                    currentIntent = "Alternative approach to avoid oscillation: \(currentIntent)"
                case .noProgress(let iterations):
                    if iterations >= 15 {
                        await triggerTakeover(reason: "Unrecoverable stagnation: No progress after \(iterations) iterations")
                        throw AutonomousError.noProgressCycle
                    } else {
                        await context.logger.warning("⚠️ No progress after \(iterations) iterations. Adjusting plan to resolve build/test failures.", toolId: "AutonomousEngine")
                        currentIntent = "Resolve previous build/test failure with fresh context: \(currentIntent)"
                    }
                case .repetitiveActions:
                    await context.logger.warning("⚠️ Repetitive actions detected - adjusting strategy", toolId: "AutonomousEngine")
                    currentIntent = "Alternative approach to break repetitive cycle: \(currentIntent)"
                case .none:
                    break
                }

                let progressPossible = progressEvaluator.isProgressBeingMade() || iterationCount < 15
                if !progressPossible {
                    await context.logger.error("⛔ Unrecoverable state: No progress detected after multiple diverse replanning attempts.", toolId: "AutonomousEngine")
                    await triggerTakeover(reason: "No meaningful progress after 15 diverse attempts")
                    throw AutonomousError.noProgressCycle
                }

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
                    currentIntent = "Retry step \(stepIndex): \(validationResult.feedback). Original: \(currentIntent)"

                case .replanTask(let feedback):
                    await context.logger.info("📋 Decision: Replan with feedback", toolId: "AutonomousEngine")
                    currentIntent = "Previous attempt failed. Feedback: \(feedback). Original goal: \(originalIntent)"

                case .optimizeOutput:
                    await context.logger.info("⚡ Decision: Optimize output", toolId: "AutonomousEngine")

                case .triggerTakeover(let reason):
                    await triggerTakeover(reason: reason)
                    throw AutonomousError.decisionEngineEscalation
                }

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

                if iterationCount >= 50 {
                    await context.logger.error("⛔ Safe execution guardrail reached (50 iterations)", toolId: "AutonomousEngine")
                    await triggerTakeover(reason: "Runaway safety guardrail (50 iterations) reached for current task.")
                    throw AutonomousError.maxIterationsReached
                }
            }
        }

        await context.logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", toolId: "AutonomousEngine")
        await context.logger.info("🎉 AUTONOMOUS EXECUTION SUMMARY", toolId: "AutonomousEngine")
        await context.logger.info("Tasks completed: \(completedTasks.count)", toolId: "AutonomousEngine")
        await context.logger.info("Total iterations: \(iterationCount)", toolId: "AutonomousEngine")
        await context.logger.info(progressEvaluator.getSummary(), toolId: "AutonomousEngine")

        let trace = traceEngine.exportTrace()
        await context.logger.info("Execution trace exported (\(trace.count) chars)", toolId: "AutonomousEngine")
    }

    private func triggerTakeover(reason: String) async {
        await MainActor.run {
            AssistManager.shared.takeoverReason = reason
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
