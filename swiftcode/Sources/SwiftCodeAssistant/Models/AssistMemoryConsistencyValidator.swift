import Foundation

@MainActor
public final class AssistMemoryConsistencyValidator {
    private let context: AssistContext

    public struct ConsistencyReport {
        let isConsistent: Bool
        let issues: [String]
    }

    public init(context: AssistContext) {
        self.context = context
    }

    public func validateConsistency() async -> ConsistencyReport {
        await context.logger.info("Validating memory consistency", toolId: "MemoryValidator")

        var issues: [String] = []

        if context.project == nil {
            issues.append("No active project in context")
        }

        if !FileManager.default.fileExists(atPath: context.workspaceRoot.path) {
            issues.append("Workspace root does not exist: \(context.workspaceRoot.path)")
        }

        let isConsistent = issues.isEmpty

        if !isConsistent {
            await context.logger.warning("Memory consistency issues found: \(issues.joined(separator: ", "))", toolId: "MemoryValidator")
        }

        return ConsistencyReport(isConsistent: isConsistent, issues: issues)
    }
}
