import Foundation

public struct AgentContext: Sendable, Codable {
    public let repoManifestSummary: String
    public let taskObjective: String
    public let currentPlan: AssistExecutionPlan?
    public let completedActions: [String]
    public let remainingActions: [String]
    public let activeFileContents: [String: String]
    public let recentToolResults: [String]
    public let recentBuildErrors: [String]
    public let repositoryInstructions: String
    public let failureHistorySummary: String
    public let verificationStatusSummary: String

    public init(
        repoManifestSummary: String,
        taskObjective: String,
        currentPlan: AssistExecutionPlan? = nil,
        completedActions: [String] = [],
        remainingActions: [String] = [],
        activeFileContents: [String: String] = [:],
        recentToolResults: [String] = [],
        recentBuildErrors: [String] = [],
        repositoryInstructions: String = "",
        failureHistorySummary: String = "",
        verificationStatusSummary: String = ""
    ) {
        self.repoManifestSummary = repoManifestSummary
        self.taskObjective = taskObjective
        self.currentPlan = currentPlan
        self.completedActions = completedActions
        self.remainingActions = remainingActions
        self.activeFileContents = activeFileContents
        self.recentToolResults = recentToolResults
        self.recentBuildErrors = recentBuildErrors
        self.repositoryInstructions = repositoryInstructions
        self.failureHistorySummary = failureHistorySummary
        self.verificationStatusSummary = verificationStatusSummary
    }
}

public final class AgentContextManager: Sendable {
    private let context: AssistContext

    public init(context: AssistContext) {
        self.context = context
    }

    /// Assembles a token-efficient, layered, prioritized project and task context.
    public func buildContext(
        for objective: String,
        plan: AssistExecutionPlan? = nil,
        completedActions: [String] = [],
        remainingActions: [String] = [],
        recentResults: [AssistToolResult] = [],
        recentErrors: [String] = [],
        failureSummary: String = "",
        verificationSummary: String = "",
        activeFiles: [String] = []
    ) async -> AgentContext {
        // Priority 1: Grounded Repository Manifest
        let projectName = context.project?.name ?? "SwiftCode"
        let manifest = "Workspace root: \(context.workspaceRoot.path)\nActive project: \(projectName)"

        // Priority 2: Repository Instructions & Grounding (AGENTS.md / README.md)
        var repoInstructions = ""
        let groundingFiles = ["AGENTS.md", "CLAUDE.md", "README.md", "Package.swift"]
        for gFile in groundingFiles {
            if context.fileSystem.exists(at: gFile) {
                if let raw = try? context.fileSystem.readFile(at: gFile) {
                    let maxChars = 3000
                    let snippet = raw.count > maxChars ? String(raw.prefix(maxChars)) + "\n... [TRUNCATED]" : raw
                    repoInstructions += "\n--- [GROUNDING: \(gFile)] ---\n\(snippet)\n"
                    break // Prefer AGENTS.md if available
                }
            }
        }

        // Priority 3: Active target files
        var activeContents: [String: String] = [:]
        for file in activeFiles.prefix(6) {
            if context.fileSystem.exists(at: file) {
                if let content = try? context.fileSystem.readFile(at: file) {
                    let maxChars = 4000
                    if content.count > maxChars {
                        activeContents[file] = String(content.prefix(maxChars)) + "\n... [TRUNCATED]"
                    } else {
                        activeContents[file] = content
                    }
                }
            }
        }

        // Priority 4: Compact recent observations (prevent context explosion)
        var compactResults: [String] = []
        for res in recentResults.suffix(5) {
            let maxOutput = 1200
            let body = res.output.count > maxOutput ? String(res.output.prefix(maxOutput)) + "\n... [OUTPUT TRUNCATED]" : res.output
            var item = "Status: \(res.success ? "SUCCESS" : "FAILED")\nOutput: \(body)"
            if let diff = res.diff, !diff.isEmpty {
                let maxDiff = 800
                let diffSummary = diff.count > maxDiff ? String(diff.prefix(maxDiff)) + "\n... [DIFF TRUNCATED]" : diff
                item += "\nDiff:\n\(diffSummary)"
            }
            if !res.diagnostics.isEmpty {
                item += "\nDiagnostics: \(res.diagnostics.prefix(3).joined(separator: "; "))"
            }
            compactResults.append(item)
        }

        return AgentContext(
            repoManifestSummary: manifest,
            taskObjective: objective,
            currentPlan: plan,
            completedActions: completedActions,
            remainingActions: remainingActions,
            activeFileContents: activeContents,
            recentToolResults: compactResults,
            recentBuildErrors: Array(recentErrors.suffix(5)),
            repositoryInstructions: repoInstructions,
            failureHistorySummary: failureSummary,
            verificationStatusSummary: verificationSummary
        )
    }
}
