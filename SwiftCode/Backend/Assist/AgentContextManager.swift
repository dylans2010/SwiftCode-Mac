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

    public init(
        repoManifestSummary: String,
        taskObjective: String,
        currentPlan: AssistExecutionPlan? = nil,
        completedActions: [String] = [],
        remainingActions: [String] = [],
        activeFileContents: [String: String] = [:],
        recentToolResults: [String] = [],
        recentBuildErrors: [String] = []
    ) {
        self.repoManifestSummary = repoManifestSummary
        self.taskObjective = taskObjective
        self.currentPlan = currentPlan
        self.completedActions = completedActions
        self.remainingActions = remainingActions
        self.activeFileContents = activeFileContents
        self.recentToolResults = recentToolResults
        self.recentBuildErrors = recentBuildErrors
    }
}

public final class AgentContextManager: Sendable {
    private let context: AssistContext

    public init(context: AssistContext) {
        self.context = context
    }

    /// Assembles a token-efficient, prioritized project and task context.
    public func buildContext(for objective: String) async -> AgentContext {
        let manifest = "Workspace root: \(context.workspaceRoot.path)\nActive project: \(context.project?.name ?? "None")"

        // Priority 1 & 2: Manifest summary + Task objective
        var activeContents: [String: String] = [:]

        // Priority 3: Full contents of active/modified files
        if context.fileSystem.exists(at: "README.md") {
            if let content = try? context.fileSystem.readFile(at: "README.md") {
                // Ensure content is capped to prevent budget exhaustion
                let maxChars = 2000
                if content.count > maxChars {
                    activeContents["README.md"] = String(content.prefix(maxChars)) + "\n... [TRUNCATED]"
                } else {
                    activeContents["README.md"] = content
                }
            }
        }

        return AgentContext(
            repoManifestSummary: manifest,
            taskObjective: objective,
            currentPlan: nil,
            completedActions: [],
            remainingActions: [],
            activeFileContents: activeContents,
            recentToolResults: [],
            recentBuildErrors: []
        )
    }
}
