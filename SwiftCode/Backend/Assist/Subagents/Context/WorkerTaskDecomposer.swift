import Foundation
import os

/// Decomposes complex coding tasks into isolated Worker assignments using Apple Foundation Models or parent Assist LLM fallback.
/// Strictly decomposes only; never writes production code itself (F-DECOMP).
@MainActor
public final class WorkerTaskDecomposer: Sendable {
    public static let shared = WorkerTaskDecomposer()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerTaskDecomposer")

    private init() {}

    /// Determines if a task is sufficiently large to warrant autonomous multi-Worker decomposition.
    public func shouldDecompose(objective: String) -> Bool {
        let isCapabilityEnabled = UserDefaults.standard.object(forKey: "assist.useSubagents") == nil ? true : UserDefaults.standard.bool(forKey: "assist.useSubagents")
        guard isCapabilityEnabled else { return false }

        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 30 { return false }

        let lower = trimmed.lowercased()
        let complexIndicators = [
            "and", "also", "build", "create", "implement", "refactor",
            "ui", "backend", "test", "database", "api", "model", "view",
            "feature", "pipeline", "system", "fix", "repair", "overhaul"
        ]

        let matchedCount = complexIndicators.filter { lower.contains($0) }.count
        // Multi-domain scope indicator: task contains multiple domain verbs/nouns or is long (> 100 chars)
        return matchedCount >= 2 || trimmed.count > 120
    }

    /// Decomposes an objective into non-overlapping Worker assignments.
    public func decompose(
        objective: String,
        repoSummary: String,
        context: AssistContext
    ) async -> [WorkerAssignment] {
        logger.info("Decomposing objective: \(objective.prefix(80))...")

        // 1. Try Apple Foundation Model if available on-device
        if FoundationModels.shared.isEnabled {
            if let afmAssignments = await decomposeWithFoundationModels(objective: objective, repoSummary: repoSummary) {
                if validateAssignments(afmAssignments) {
                    logger.info("AFM decomposition succeeded with \(afmAssignments.count) workers.")
                    return afmAssignments
                }
            }
        }

        // 2. Fallback to Parent Assist LLM
        if let llmAssignments = await decomposeWithParentLLM(objective: objective, repoSummary: repoSummary) {
            if validateAssignments(llmAssignments) {
                logger.info("Parent LLM decomposition succeeded with \(llmAssignments.count) workers.")
                return llmAssignments
            }
        }

        // 3. Deterministic engineering breakdown fallback (never fabricates fake data, guarantees real partition)
        return synthesizeDeterministicBreakdown(for: objective)
    }

    // MARK: - Foundation Model Path

    private func decomposeWithFoundationModels(objective: String, repoSummary: String) async -> [WorkerAssignment]? {
        let prompt = buildDecompositionPrompt(objective: objective, repoSummary: repoSummary)
        do {
            let response = try await FoundationModels.shared.generatePrivateResponse(prompt: prompt)
            return parseAssignments(from: response)
        } catch {
            logger.warning("Foundation Model decomposition error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Parent LLM Path

    private func decomposeWithParentLLM(objective: String, repoSummary: String) async -> [WorkerAssignment]? {
        let prompt = buildDecompositionPrompt(objective: objective, repoSummary: repoSummary)

        do {
            let activeModel = AssistModelManager.shared.selectedModelID
            let response = try await LLMService.shared.generateResponse(
                prompt: prompt,
                useContext: false,
                modelOverride: activeModel.isEmpty ? nil : activeModel
            )
            return parseAssignments(from: response)
        } catch {
            logger.warning("Parent LLM decomposition error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Prompt & Parsing

    private func buildDecompositionPrompt(objective: String, repoSummary: String) -> String {
        return """
        Decompose this software development task into 2 to 4 distinct, non-overlapping Worker assignments.
        Each worker must have an isolated scope and clear responsibility.

        Task Objective: "\(objective)"
        Repository Structure:
        \(repoSummary.prefix(1500))

        Respond ONLY with a valid JSON array of worker objects in exactly this format:
        [
          {
            "name": "Specific Worker Name",
            "role": "Architecture | UI | Backend | Testing | Swift",
            "scope": "Clear non-overlapping file/module boundary",
            "task": "Precise task description under 500 characters",
            "dependencies": []
          }
        ]
        """
    }

    private func parseAssignments(from text: String) -> [WorkerAssignment]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        var jsonString = trimmed
        if let start = trimmed.range(of: "["),
           let end = trimmed.range(of: "]", options: .backwards) {
            jsonString = String(trimmed[start.lowerBound...end.upperBound])
        }

        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var results: [WorkerAssignment] = []
        for dict in array {
            guard let name = dict["name"] as? String,
                  let scope = dict["scope"] as? String,
                  let task = dict["task"] as? String else {
                continue
            }
            let role = dict["role"] as? String ?? "General Engineer"
            let deps = dict["dependencies"] as? [String] ?? []

            let assignment = WorkerAssignment(
                name: name,
                scope: scope,
                task: String(task.prefix(500)),
                role: role,
                dependencies: deps
            )
            results.append(assignment)
        }

        return results.isEmpty ? nil : results
    }

    // MARK: - Validation & Deterministic Fallback

    public func validateAssignments(_ assignments: [WorkerAssignment]) -> Bool {
        guard !assignments.isEmpty else { return false }

        var names = Set<String>()
        for a in assignments {
            if a.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if a.scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if a.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if a.task.count > 500 { return false }
            if names.contains(a.name) { return false } // No duplicates (INV-7)
            names.insert(a.name)
        }

        return true
    }

    private func synthesizeDeterministicBreakdown(for objective: String) -> [WorkerAssignment] {
        return [
            WorkerAssignment(
                name: "Core Implementation Worker",
                scope: "Domain Models & Logic",
                task: "Implement core domain structures and mutations for: \(objective.prefix(350))",
                role: "Backend & Logic",
                dependencies: []
            ),
            WorkerAssignment(
                name: "Verification & QA Worker",
                scope: "Testing & Validation",
                task: "Validate syntax, run compiler checks, and verify integrity of implementation.",
                role: "Testing & QA",
                dependencies: ["Core Implementation Worker"]
            )
        ]
    }
}
