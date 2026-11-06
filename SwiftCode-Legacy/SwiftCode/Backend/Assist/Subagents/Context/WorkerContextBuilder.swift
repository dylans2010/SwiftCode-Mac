import Foundation
import os

@MainActor
public final class WorkerContextBuilder: Sendable {
    public static let shared = WorkerContextBuilder()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerContextBuilder")

    private init() {}

    public func buildWorkerPrompt(
        for worker: Worker,
        assignment: WorkerAssignment,
        context: AssistContext,
        dependencyResults: [WorkerResult] = []
    ) async -> String {
        let discoveredSkills = await AgentSkillResolver.shared.discoverSkills(in: context.workspaceRoot)
        let matchedSkills = AgentSkillResolver.shared.matchSkills(for: "\(worker.role) \(worker.scope)", in: discoveredSkills)
        let skillsBlock = AgentSkillResolver.shared.formatSkillsBlock(matched: matchedSkills, totalDiscovered: discoveredSkills.count)

        let agentsInstructions = loadWorkspaceRules(root: context.workspaceRoot)
        let scopedRules = filterRelevantRules(agentsInstructions, for: worker.scope)

        let relevantFileContents = await loadRelevantFiles(
            targetFiles: assignment.targetFiles,
            scope: worker.scope,
            workspaceRoot: context.workspaceRoot
        )

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

        let excludedFiles = await identifyExcludedFiles(
            targetFiles: assignment.targetFiles,
            workspaceRoot: context.workspaceRoot
        )

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
        - YOUR TARGET FILES: \(assignment.targetFiles.isEmpty ? "None specified - infer from scope" : assignment.targetFiles.joined(separator: ", "))
        - YOUR EXCLUSIONS: Do NOT modify files outside your declared scope. Never attempt global task completion. Report any adjacent discovered work back to the orchestrator rather than absorbing it.

        ## CONTEXT ISOLATION
        You receive ONLY the context relevant to your assignment. Other workers are handling other parts of the codebase.
        Relevant files for your scope:
        \(relevantFileContents.isEmpty ? "No pre-loaded file contents. Inspect files as needed within your scope." : relevantFileContents)

        Files explicitly excluded from your scope:
        \(excludedFiles.isEmpty ? "None" : excludedFiles.joined(separator: ", "))

        ## NON-CONVERSATIONAL INVARIANT (INV-2)
        - NEVER ask the user questions or request clarification/approval/choices.
        - Infer from context -> inspect repo -> inspect AGENTS.md -> make the best engineering choice -> execute.
        - If fundamentally blocked, declare BLOCKED with a clear diagnostic explanation.

        ## WORKSPACE INSTRUCTIONS (AGENTS.MD - FILTERED FOR YOUR SCOPE)
        \(scopedRules.isEmpty ? "No specific workspace AGENTS.md rules declared for your scope." : scopedRules)

        ## RELEVANT SKILLS
        \(skillsBlock)

        \(dependencyContext)

        ## EXECUTION INSTRUCTIONS
        Fulfill your assigned task thoroughly. Make atomic, correct, and self-verifying changes.
        """

        return prompt
    }

    private func loadWorkspaceRules(root: URL) -> String {
        let candidates = ["AGENTS.md", "Agents.md", "Agent.md"]
        for candidate in candidates {
            let fileURL = root.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    return String(content.prefix(4000))
                }
            }
        }
        return ""
    }

    private func filterRelevantRules(_ rules: String, for scope: String) -> String {
        guard !rules.isEmpty else { return "" }
        let scopeKeywords = scope.lowercased().split(separator: " ").map(String.init)
        let lines = rules.components(separatedBy: .newlines)
        var relevantLines: [String] = []
        var currentSection = ""
        var currentSectionRelevant = true

        for line in lines {
            if line.hasPrefix("#") {
                currentSection = line
                currentSectionRelevant = scopeKeywords.contains { keyword in
                    line.lowercased().contains(keyword)
                } || scopeKeywords.contains { keyword in
                    scope.lowercased().contains(keyword) && line.lowercased().contains("worker")
                }
                if currentSectionRelevant {
                    relevantLines.append(line)
                }
            } else if currentSectionRelevant {
                relevantLines.append(line)
            }
        }

        return relevantLines.isEmpty ? rules : relevantLines.joined(separator: "\n")
    }

    private func loadRelevantFiles(
        targetFiles: [String],
        scope: String,
        workspaceRoot: URL
    ) async -> String {
        if targetFiles.isEmpty { return "" }

        var contents: [String] = []
        for filePath in targetFiles.prefix(10) {
            let fullPath = workspaceRoot.appendingPathComponent(filePath)
            guard FileManager.default.fileExists(atPath: fullPath.path) else { continue }
            guard let content = try? String(contentsOf: fullPath, encoding: .utf8) else { continue }
            let capped = String(content.prefix(2000))
            contents.append("### \(filePath)\n```\n\(capped)\n```")
        }
        return contents.joined(separator: "\n\n")
    }

    private func identifyExcludedFiles(
        targetFiles: [String],
        workspaceRoot: URL
    ) async -> [String] {
        let allSwiftFiles = FileManager.default.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )?.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { $0.lastPathComponent } ?? []

        let targetSet = Set(targetFiles.map { URL(fileURLWithPath: $0).lastPathComponent })
        return allSwiftFiles.filter { !targetSet.contains($0) }.sorted()
    }
}
