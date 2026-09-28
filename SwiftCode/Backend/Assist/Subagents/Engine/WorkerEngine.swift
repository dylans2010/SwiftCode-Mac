import Foundation
import os

/// Executes the autonomous lifecycle of a single Assist Worker.
/// Runs in isolation with strict scope boundaries (INV-6), executing actions non-conversationally (INV-2).
@MainActor
public final class WorkerEngine: Sendable {
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerEngine")
    private let registry = AssistToolRegistry()

    public init() {}

    /// Runs a worker through its assigned task to completion or failure
    public func execute(
        worker: Worker,
        scopedPrompt: String,
        context: AssistContext,
        modelID: String
    ) async -> WorkerResult {
        let workerID = worker.id
        let workerName = worker.name

        // Transition: STARTING -> WORKING
        WorkerRuntimeState.shared.transitionWorker(id: workerID, to: .starting, reason: "Worker initialized and loading isolated context bundle...")
        try? await Task.sleep(nanoseconds: 100_000_000)

        WorkerRuntimeState.shared.transitionWorker(id: workerID, to: .working, reason: "Executing assigned task: \(worker.task)")

        // Phase: Implementation
        var progress = WorkerProgress(
            narrative: "Executing implementation phase for scope '\(worker.scope)'",
            currentAction: "Inspecting codebase symbols and target files",
            phase: .implementation,
            nextPlan: "Perform required code mutations and file adjustments",
            percentage: 0.25
        )
        WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

        var completedWork: [String] = []
        var knownIssues: [String] = []
        var remainingWork: [String] = []

        do {
            // Check for cooperative cancellation
            if Task.isCancelled || WorkerRuntimeState.shared.workers.first(where: { $0.id == workerID })?.status == .cancelled {
                return WorkerResult(
                    workerID: workerID,
                    workerName: workerName,
                    summary: "Worker was cancelled before completion.",
                    completedWork: completedWork,
                    knownIssues: ["Cancelled by user"],
                    remainingWork: [worker.task],
                    recommendedParentAction: "Review stopped state"
                )
            }

            // Step 1: Execution & Tool Interactions
            logger.info("[Worker \(workerName)] Querying model '\(modelID)' for implementation plan...")
            progress.currentAction = "Generating mutations for \(worker.scope)"
            progress.percentage = 0.50
            WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

            let toolSchemas = registry.getToolSchemas().compactMap { schema -> String? in
                guard let name = schema["name"] as? String, let desc = schema["description"] as? String else { return nil }
                return "- \(name): \(desc)"
            }.joined(separator: "\n")

            let fullPrompt = """
            \(scopedPrompt)

            # AVAILABLE TOOLS
            \(toolSchemas)

            Begin execution of your assigned task now. Respond with JSON only:
            { "toolId": "...", "input": { "key": "value" }, "explanation": "..." }
            or { "finalResponse": "summary of completed work" }
            """

            var conversationHistory: [String] = []
            var currentModel = modelID
            var loopIterations = 0
            let maxLoopIterations = 10
            var finalResponse: String?

            while loopIterations < maxLoopIterations {
                loopIterations += 1

                if Task.isCancelled || WorkerRuntimeState.shared.workers.first(where: { $0.id == workerID })?.status == .cancelled {
                    return WorkerResult(
                        workerID: workerID,
                        workerName: workerName,
                        summary: "Worker was cancelled before completion.",
                        completedWork: completedWork,
                        knownIssues: ["Cancelled by user"],
                        remainingWork: [worker.task],
                        recommendedParentAction: "Review stopped state"
                    )
                }

                var responseText = ""
                do {
                    responseText = try await LLMService.shared.generateResponse(prompt: fullPrompt + "\n\n# RECENT RESULTS\n" + conversationHistory.suffix(6).joined(separator: "\n"), useContext: false, modelOverride: currentModel)
                } catch {
                    logger.warning("[Worker \(workerName)] Model query error: \(error.localizedDescription). Attempting recovery.")
                    if let fallback = WorkerModelSelector.shared.fallbackModel(for: currentModel) {
                        WorkerRuntimeState.shared.updateWorker(id: workerID) { w in
                            w.modelUsed = fallback
                        }
                        currentModel = fallback
                        responseText = (try? await LLMService.shared.generateResponse(prompt: fullPrompt + "\n\n# RECENT RESULTS\n" + conversationHistory.suffix(6).joined(separator: "\n"), useContext: false, modelOverride: fallback)) ?? ""
                    }
                }

                guard !responseText.isEmpty else {
                    conversationHistory.append("- System note: empty model response")
                    continue
                }

                guard let jsonBlock = AgentModelAdapter.shared.extractJSON(from: responseText) else {
                    conversationHistory.append("- System note: invalid JSON response. Respond with a tool call or finalResponse.")
                    continue
                }

                if let final = jsonBlock["finalResponse"] as? String {
                    finalResponse = final
                    break
                }

                guard let toolId = jsonBlock["toolId"] as? String,
                      let toolInput = jsonBlock["input"] as? [String: Any] else {
                    conversationHistory.append("- System note: response missing 'toolId' or 'input'.")
                    continue
                }

                guard let tool = registry.getTool(toolId) else {
                    conversationHistory.append("- Action: Run \(toolId). Result: FAILED - Tool '\(toolId)' not found.")
                    continue
                }

                do {
                    let result = try await tool.execute(input: toolInput, context: context)
                    if result.success {
                        for file in result.filesChanged {
                            let changeType: FileChangeType
                            switch toolId {
                            case "file_create": changeType = .created
                            case "file_delete": changeType = .deleted
                            case "file_rename", "file_move": changeType = .renamed
                            default: changeType = .modified
                            }
                            WorkerRuntimeState.shared.recordFileChange(id: workerID, change: WorkerFileChange(path: file, changeType: changeType))
                        }
                        completedWork.append("Executed \(toolId): \(result.output.prefix(200))")
                        conversationHistory.append("- Action: Run \(toolId). Result: SUCCESS - \(result.output.prefix(300))")
                    } else {
                        let errMsg = result.error ?? result.output
                        knownIssues.append(errMsg)
                        conversationHistory.append("- Action: Run \(toolId). Result: FAILED - \(errMsg)")
                    }
                } catch {
                    conversationHistory.append("- Action: Run \(toolId). Result: FAILED - Exception: \(error.localizedDescription)")
                }
            }

            if let final = finalResponse {
                completedWork.append(final)
            } else {
                remainingWork.append(worker.task)
            }

            // Phase: Testing & QA
            progress.phase = .testing
            progress.currentAction = "Reviewing executed changes"
            progress.percentage = 0.75
            WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

            // Phase: Verification
            progress.phase = .verification
            progress.currentAction = "Auditing AST and boundary rules"
            progress.percentage = 0.90
            WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

            let workerState = WorkerRuntimeState.shared.workers.first(where: { $0.id == workerID })
            let verificationState = finalResponse != nil ? "Completed" : "Incomplete"
            WorkerRuntimeState.shared.updateWorker(id: workerID) { w in
                w.verificationState = verificationState
                w.recap = completedWork
            }

            // Transition: REVIEWING
            WorkerRuntimeState.shared.transitionWorker(
                id: workerID,
                to: .reviewing,
                reason: "Implementation complete. Awaiting parent Assist review gate."
            )

            let result = WorkerResult(
                workerID: workerID,
                workerName: workerName,
                summary: finalResponse != nil
                    ? "Fulfilled scope '\(worker.scope)'. Task: \(worker.task)"
                    : "Incomplete scope '\(worker.scope)': model did not return a final response within \(maxLoopIterations) iterations.",
                completedWork: completedWork,
                modifiedFiles: workerState?.modifiedFiles.map { $0.path } ?? [],
                createdFiles: workerState?.createdFiles.map { $0.path } ?? [],
                deletedFiles: workerState?.deletedFiles.map { $0.path } ?? [],
                tests: [],
                buildResult: "Not executed",
                verificationResult: finalResponse != nil ? "Tool execution completed; build not run" : "Incomplete",
                knownIssues: knownIssues,
                remainingWork: remainingWork,
                recommendedParentAction: finalResponse != nil ? "Accept and integrate results" : "Re-execute or reassign remaining scope"
            )

            return result

        } catch {
            logger.error("[Worker \(workerName)] Failure during execution: \(error.localizedDescription)")
            let workerError = WorkerError(
                code: "EXECUTION_ERROR",
                message: error.localizedDescription,
                recoverable: true,
                rootCause: "Uncaught exception in Worker execution loop",
                remedy: "Engage WorkerRecoveryEngine or parent repair assignment"
            )

            WorkerRuntimeState.shared.updateWorker(id: workerID) { w in
                w.errorState = workerError
                w.status = .failed
                w.currentAction = "Failed: \(error.localizedDescription)"
            }

            WorkerRuntimeState.shared.transitionWorker(
                id: workerID,
                to: .failed,
                reason: "Execution failure: \(error.localizedDescription)"
            )

            return WorkerResult(
                workerID: workerID,
                workerName: workerName,
                summary: "Worker encountered failure: \(error.localizedDescription)",
                completedWork: completedWork,
                knownIssues: [error.localizedDescription],
                remainingWork: [worker.task],
                recommendedParentAction: "Repair or reassign remaining scope"
            )
        }
    }
}
