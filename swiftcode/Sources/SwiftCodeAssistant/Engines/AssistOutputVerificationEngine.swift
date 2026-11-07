import Foundation

@MainActor
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

    public func verify(plan: AssistExecutionPlan) async -> VerificationResult {
        await context.logger.info("Verifying output completeness for: \(plan.goal)", toolId: "OutputVerification")

        var issues: [String] = []
        var suggestions: [String] = []

        for step in plan.steps where step.result == nil {
            issues.append("Step '\(step.description)' has no result")
            suggestions.append("Ensure step was executed")
        }

        for step in plan.steps where step.status == .running {
            issues.append("Step '\(step.description)' is still marked as running")
            suggestions.append("Complete or fail stuck steps before finishing")
        }

        for step in plan.steps where step.status == .completed {
            if let result = step.result, !result.success {
                issues.append("Step '\(step.description)' completed but reports failure: \(result.error ?? "unknown error")")
                suggestions.append("Re-execute step and inspect error output")
            }
        }

        for step in plan.steps where ["file_write", "createFile", "generateFile"].contains(step.toolId) {
            if let path = step.input["path"], step.status == .completed {
                if !context.fileSystem.exists(at: path) {
                    issues.append("File '\(path)' was supposed to be created but doesn't exist")
                    suggestions.append("Re-execute file creation step")
                    continue
                }
                if let content = try? context.fileSystem.readFile(at: path) {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        issues.append("File '\(path)' is empty")
                        suggestions.append("Generate complete implementation")
                    } else if content.count < 50 || assistContainsPlaceholderToken(content) {
                        issues.append("File '\(path)' appears to be incomplete or placeholder")
                        suggestions.append("Generate complete implementation")
                    }
                    if assistHasConflictMarkers(content) {
                        issues.append("File '\(path)' contains unresolved merge conflict markers")
                        suggestions.append("Resolve conflict markers in file")
                    }
                }
            }
        }

        let failedSteps = plan.steps.filter { $0.status == .failed }
        if !failedSteps.isEmpty {
            issues.append("\(failedSteps.count) step(s) failed")
            suggestions.append("Review and retry failed steps")
        }

        let buildOutcome = await AssistVerificationPipeline.shared.verifyCompilation(context: context)
        if !buildOutcome.isSuccess {
            issues.append("Independent build verification failed: \(buildOutcome.error ?? "compilation errors")")
            suggestions.append("Run project_build and fix compiler errors")
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
