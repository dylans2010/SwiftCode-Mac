import Foundation
import os

/// Automatically evaluates completed tasks, generates logical follow-up goals,
/// enforces anti-runaway safeguards, and expands task scope under continuous autonomous takeover.
@MainActor
public final class AssistGoalExpansionEngine: Sendable {
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistGoalExpansionEngine")

    public init() {}
    public init(context: AssistContext) {}

    /// Backward-compatible overload for legacy Assist engine workflows.
    public func expandGoals(
        originalGoal: String,
        completedPlan: AssistExecutionPlan? = nil
    ) async -> [String] {
        let session = AssistTakeoverSessionState.shared

        guard session.consecutiveFailures < AssistGoalSafeguards.maxConsecutiveFailures else {
            logger.warning("[GoalExpansion] Circuit breaker active (\(session.consecutiveFailures) consecutive failures). Halting expansion.")
            return []
        }

        let completedNode: AssistGoal
        if let existing = session.goalGraph.goal(withTitle: originalGoal) {
            completedNode = existing
        } else {
            completedNode = AssistGoal(
                title: originalGoal,
                detailedObjective: originalGoal,
                status: .completed,
                provenance: GoalProvenance(
                    createdReason: "Root user goal",
                    evidenceTrigger: "User request",
                    relationshipToRoot: "Root goal",
                    parentGoalId: nil,
                    generationDepth: 0,
                    timestamp: Date()
                ),
                dependencies: [],
                expectedOutcome: "Successful plan execution"
            )
            session.goalGraph.setRoot(originalGoal)
            session.goalGraph.add(completedNode)
        }
        session.goalGraph.markCompleted(id: completedNode.id)

        var modifiedFiles: [String] = []
        if let plan = completedPlan {
            for step in plan.steps {
                if let file = step.input["path"] ?? step.input["filePath"] ?? step.input["targetFile"] {
                    modifiedFiles.append(file)
                }
            }
        }

        let rootGoal = session.goalGraph.rootGoal.isEmpty ? originalGoal : session.goalGraph.rootGoal

        let expanded = await expandGoals(
            completedGoal: completedNode,
            existingGoals: session.goalGraph.goals,
            rootGoal: rootGoal,
            modifiedFiles: modifiedFiles,
            consecutiveFailures: session.consecutiveFailures
        )

        for goal in expanded {
            session.goalGraph.add(goal)
        }

        return expanded.map { $0.title }
    }

    /// Generates structured follow-up goals based on a completed goal and repository observations.
    public func expandGoals(
        completedGoal: AssistGoal,
        existingGoals: [AssistGoal],
        rootGoal: String,
        modifiedFiles: [String],
        consecutiveFailures: Int = 0
    ) async -> [AssistGoal] {
        logger.info("[GoalExpansion] Evaluating expansion candidates from completed goal: '\(completedGoal.title)'")

        guard completedGoal.status == .completed else {
            logger.info("[GoalExpansion] Skipping expansion: goal '\(completedGoal.title)' did not complete successfully")
            return []
        }

        let currentDepth = completedGoal.provenance.generationDepth + 1

        // Check if safeguards prevent further expansion before prompting
        if existingGoals.count >= AssistGoalSafeguards.maxTotalExpandedGoals || currentDepth > AssistGoalSafeguards.maxDepth {
            logger.warning("[GoalExpansion] Safeguards limit reached. Halting autonomous expansion.")
            return []
        }

        // Try AI-driven candidate generation first
        var candidatePairs: [(title: String, objective: String, reason: String, expected: String)] = []

        let prompt = """
        # CONTINUOUS AUTONOMOUS TAKEOVER: GOAL EXPANSION
        Root User Goal: "\(rootGoal)"
        Just Completed Goal: "\(completedGoal.title)"
        Modified Files: \(modifiedFiles.joined(separator: ", "))

        You are the autonomous engineering coordinator.
        Suggest 1 to 2 strictly necessary follow-up engineering goals that naturally complete this work.
        Valid expansion categories:
        1. Unit Test Coverage: Adding unit tests for the modified files.
        2. Documentation: Adding DocC or README architecture notes for newly introduced interfaces.
        3. Edge Case Hardening: Adding input validation, concurrency safety, or error handling.

        Respond ONLY with a JSON array formatted exactly like:
        [
          {
            "title": "Add Unit Tests for <Component>",
            "objective": "Write comprehensive unit tests covering edge cases and happy path for <Component>",
            "reason": "Ensure regression prevention for recently created/modified files",
            "expectedOutcome": "All test assertions pass cleanly with zero compiler warnings"
          }
        ]
        """

        do {
            let activeModel = AssistModelManager.shared.selectedModelID
            let response = try await AgentModelAdapter.shared.queryModel(prompt: prompt, modelId: activeModel, maxRetries: 1)
            candidatePairs = parseGoalCandidates(from: response)
        } catch {
            logger.warning("[GoalExpansion] Model query for expansion failed or offline: \(error.localizedDescription). Falling back to deterministic synthesis.")
        }

        // Fallback: Deterministic engineering synthesis if model output is unavailable
        if candidatePairs.isEmpty {
            candidatePairs = synthesizeDeterministicCandidates(
                completedGoal: completedGoal,
                modifiedFiles: modifiedFiles
            )
        }

        var validatedGoals: [AssistGoal] = []

        for candidate in candidatePairs {
            let validation = AssistGoalSafeguards.validateCandidate(
                candidateTitle: candidate.title,
                candidateObjective: candidate.objective,
                existingGoals: existingGoals + validatedGoals,
                rootGoal: rootGoal,
                depth: currentDepth,
                consecutiveFailures: consecutiveFailures
            )

            if validation.isValid {
                let provenance = GoalProvenance(
                    createdReason: candidate.reason,
                    evidenceTrigger: "Completed goal '\(completedGoal.title)' with \(modifiedFiles.count) modified files",
                    relationshipToRoot: "Extends root task '\(rootGoal)' with necessary engineering completion",
                    parentGoalId: completedGoal.id,
                    generationDepth: currentDepth,
                    timestamp: Date()
                )

                let newGoal = AssistGoal(
                    title: candidate.title,
                    detailedObjective: candidate.objective,
                    status: .pending,
                    provenance: provenance,
                    dependencies: [completedGoal.id],
                    expectedOutcome: candidate.expected
                )

                validatedGoals.append(newGoal)
                logger.info("[GoalExpansion] Validated new goal: '\(newGoal.title)' (Depth: \(currentDepth))")

                DiagnosticEventBus.shared.logEvent(
                    component: "AssistGoalExpansionEngine",
                    severity: "INFO",
                    category: "goal_expansion",
                    message: "Synthesized valid follow-up goal: '\(newGoal.title)'"
                )
            } else {
                logger.info("[GoalExpansion] Rejected candidate '\(candidate.title)': \(validation.rejectionReason ?? "unknown")")
            }
        }

        return validatedGoals
    }

    /// Deterministic heuristics for continuous engineering when LLM is unavailable or offline.
    private func synthesizeDeterministicCandidates(
        completedGoal: AssistGoal,
        modifiedFiles: [String]
    ) -> [(title: String, objective: String, reason: String, expected: String)] {
        var candidates: [(title: String, objective: String, reason: String, expected: String)] = []

        let swiftFiles = modifiedFiles.filter { $0.hasSuffix(".swift") && !$0.contains("Test") }

        // Heuristic 1: Add Unit Tests
        if !swiftFiles.isEmpty {
            let primaryFile = (swiftFiles.first as NSString?)?.lastPathComponent ?? "Component"
            let componentName = primaryFile.replacingOccurrences(of: ".swift", with: "")

            candidates.append((
                title: "Add Unit Tests for \(componentName)",
                objective: "Implement automated unit tests validating functional requirements and boundary conditions for \(componentName).",
                reason: "Modified files require test coverage to verify stability.",
                expected: "All unit tests compile and pass successfully."
            ))

            // Heuristic 2: Edge Case Hardening
            candidates.append((
                title: "Harden Edge Cases for \(componentName)",
                objective: "Add input validation, concurrency safety, and error handling to \(componentName) covering boundary and failure conditions.",
                reason: "Modified files require edge-case hardening to prevent regressions.",
                expected: "Edge cases handled with zero compiler warnings."
            ))
        } else if !modifiedFiles.isEmpty {
            // Heuristic 3: Architecture Documentation
            candidates.append((
                title: "Document Architecture and Interface Contracts",
                objective: "Add DocC and documentation comments for public interfaces modified during the task.",
                reason: "Maintain codebase clarity and documentation integrity.",
                expected: "Documentation comments complete with clean formatting."
            ))
        }

        return candidates
    }

    private func parseGoalCandidates(from response: String) -> [(title: String, objective: String, reason: String, expected: String)] {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.contains("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Attempt array decode
        if let data = cleaned.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.compactMap { dict in
                guard let title = dict["title"] as? String,
                      let obj = dict["objective"] as? String else { return nil }
                let reason = dict["reason"] as? String ?? "Follow-up required"
                let expected = dict["expectedOutcome"] as? String ?? "Goal verified"
                return (title, obj, reason, expected)
            }
        }

        // Check for markdown code fences
        if let jsonBlock = AgentModelAdapter.shared.extractJSON(from: response) {
            if let title = jsonBlock["title"] as? String,
               let obj = jsonBlock["objective"] as? String {
                let reason = jsonBlock["reason"] as? String ?? "Follow-up required"
                let expected = jsonBlock["expectedOutcome"] as? String ?? "Goal verified"
                return [(title, obj, reason, expected)]
            }
        }

        return []
    }
}
