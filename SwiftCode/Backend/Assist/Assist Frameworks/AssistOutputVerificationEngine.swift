import Foundation

/// Verifies that generated outputs are complete and correct
public final class AssistOutputVerificationEngine {
    private let context: AssistContext

    public struct VerificationResult {
        let isComplete: Bool
        let issues: [String]
        let suggestions: [String]
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Verifies the completeness of execution outputs
    public func verify(plan: AssistExecutionPlan) async -> VerificationResult {
        await context.logger.info("Verifying output completeness for: \(plan.goal)", toolId: "OutputVerification")

        var issues: [String] = []
        var suggestions: [String] = []

        // Check 1: All steps have results
        for step in plan.steps where step.result == nil {
            issues.append("Step '\(step.description)' has no result")
            suggestions.append("Ensure step was executed")
        }

        // Check 2: File operations produced actual files
        for step in plan.steps where ["file_write", "createFile", "generateFile"].contains(step.toolId) {
            if let path = step.input["path"], step.status == .completed {
                if !context.fileSystem.exists(at: path) {
                    issues.append("File '\(path)' was supposed to be created but doesn't exist")
                    suggestions.append("Re-execute file creation step")
                }
            }
        }

        // Check 3: Files are not empty or stub-only
        for step in plan.steps where ["file_write", "createFile", "generateFile"].contains(step.toolId) {
            if let path = step.input["path"], step.status == .completed {
                if let content = try? context.fileSystem.readFile(at: path) {
                    if content.count < 50 || content.contains("TODO") || content.contains("PLACEHOLDER") {
                        issues.append("File '\(path)' appears to be incomplete or placeholder")
                        suggestions.append("Generate complete implementation")
                    }
                }
            }
        }

        // Check 4: No failed steps
        let failedSteps = plan.steps.filter { $0.status == .failed }
        if !failedSteps.isEmpty {
            issues.append("\(failedSteps.count) step(s) failed")
            suggestions.append("Review and retry failed steps")
        }

        let isComplete = issues.isEmpty

        if !isComplete {
            await context.logger.warning("Output verification found \(issues.count) issue(s)", toolId: "OutputVerification")
        }

        return VerificationResult(
            isComplete: isComplete,
            issues: issues,
            suggestions: suggestions
        )
    }
}
