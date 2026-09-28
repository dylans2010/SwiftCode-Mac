import Foundation
import os

/// Builds strictly isolated execution context bundles for Assist Workers per INV-6.
/// Enforces boundaries: "YOUR SCOPE / YOUR RESPONSIBILITIES / YOUR EXCLUSIONS".
@MainActor
public final class WorkerContextBuilder: Sendable {
    public static let shared = WorkerContextBuilder()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerContextBuilder")

    private init() {}

    /// Builds a scoped isolated system prompt and instructions for a specific Worker
    public func buildWorkerPrompt(
        for worker: Worker,
        assignment: WorkerAssignment,
        context: AssistContext,
        dependencyResults: [WorkerResult] = []
    ) async -> String {
        // 1. Discover relevant Skills for this Worker's role and scope
        let discoveredSkills = await AgentSkillResolver.shared.discoverSkills(in: context.workspaceRoot)
        let matchedSkills = AgentSkillResolver.shared.matchSkills(for: "\(worker.role) \(worker.scope)", in: discoveredSkills)
        let skillsBlock = AgentSkillResolver.shared.formatSkillsBlock(matched: matchedSkills, totalDiscovered: discoveredSkills.count)

        // 2. Discover AGENTS.md instructions in the workspace
        let agentsInstructions = loadWorkspaceRules(root: context.workspaceRoot)

        // 3. Format dependency results if this worker depends on previous workers
        var dependencyContext = ""
        if !dependencyResults.isEmpty {
            dependencyContext = "## DEPENDENCY OUTPUTS FROM PRIOR WORKERS\n"
            for result in dependencyResults {
                dependencyContext += "- Worker '\(result.workerName)': \(result.summary)\n"
                if !result.modifiedFiles.isEmpty {
                    dependencyContext += "  Modified Files: \(result.modifiedFiles.joined(separator: ", "))\n"
                }
                if !result.completedWork.isEmpty {
                    dependencyContext += "  Milestones: \(result.completedWork.joined(separator: " | "))\n"
                }
            }
        }

        // 4. Construct the authoritative isolated contract prompt
        let prompt = """
        # ASSIST WORKER OPERATING POLICY (ISOLATED EXECUTION)

        You are an autonomous Assist Worker executing as part of the SwiftCode development team.
        You are operating in ISOLATION under the direction of the Parent Assist Orchestrator.

        ## WORKER IDENTITY & CONTRACT
        - Worker ID: \(worker.id.uuidString)
        - Worker Name: "\(worker.name)"
        - Assigned Role: "\(worker.role)"
        - Parent Task ID: \(worker.parentTaskID.uuidString)

        ## MANDATORY SCOPE BOUNDARIES (INV-6, INV-8)
        - YOUR SCOPE: "\(worker.scope)"
        - YOUR RESPONSIBILITIES: "\(worker.task)"
        - YOUR EXCLUSIONS: Do NOT modify files outside your declared scope. Never attempt global task completion. Report any adjacent discovered work back to the orchestrator rather than absorbing it.

        ## NON-CONVERSATIONAL INVARIANT (INV-2)
        - NEVER ask the user questions or request clarification/approval/choices.
        - Infer from context -> inspect repo -> inspect AGENTS.md -> make the best engineering choice -> execute.
        - If fundamentally blocked, declare BLOCKED with a clear diagnostic explanation.

        ## WORKSPACE INSTRUCTIONS (AGENTS.MD)
        \(agentsInstructions.isEmpty ? "No specific workspace AGENTS.md rules declared." : agentsInstructions)

        ## RELEVANT SKILLS
        \(skillsBlock)

        \(dependencyContext)

        ## EXECUTION INSTRUCTIONS
        Fulfill your assigned task thoroughly. Make atomic, correct, and self-verifying changes.
        """

        return prompt
    }

    /// Loads AGENTS.md / Agents.md / Agent.md instructions from workspace
    private func loadWorkspaceRules(root: URL) -> String {
        let candidates = ["AGENTS.md", "Agents.md", "Agent.md"]
        for candidate in candidates {
            let fileURL = root.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    return String(content.prefix(4000)) // Cap to avoid context overflow
                }
            }
        }
        return ""
    }
}
