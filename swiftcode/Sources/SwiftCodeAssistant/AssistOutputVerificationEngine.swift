// STAGED PORT — SwiftCode-Legacy `Backend/Assist/Assist Frameworks/AssistOutputVerificationEngine.swift`
// (Legacy main d51a8f0d; Dylan's own code, direct port authorised under MIT).
// Target: SwiftCodeAssistant. Body is Legacy verbatim unless noted below.
// Dependency of _AssistCriticalAutonomousEngine (output-verification phase). Ledger SUPERSEDED by SwiftCodeMCP/SwiftCodeTools+ReviewDocs.swift — same note as AssistFailureRootCauseAnalyzer: MCP tool surface, non-importable, no VerificationResult class API. Ported verbatim.
// BLOCKED sub-dep: AssistVerificationPipeline.shared.verifyCompilation(context:) (Legacy Backend/Assist/AssistVerificationPipeline.swift, 534 lines, itself depends on ProcessRunnerTool) — not in this batch's scope; the call is kept and the pipeline is recorded blocked in _notes/agent-frameworks-decisions.md. The placeholder/conflict-marker helpers are reproduced below as file-private copies of the pipeline file's `internal` helpers so this file does not depend on the pipeline for those; if the pipeline is later ported, delete these copies and use the shared ones.
// Remaining deps (now staged in AssistModels.swift by the parallel port — see _notes/agent-models-decisions.md): AssistContext (logger, fileSystem), AssistExecutionPlan/AssistExecutionStep/AssistExecutionStatus/AssistToolResult.

import Foundation

/// Verifies that generated outputs are complete and correct
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

    /// Verifies the completeness of execution outputs against disk reality and the compiler.
    public func verify(plan: AssistExecutionPlan) async -> VerificationResult {
        await context.logger.info("Verifying output completeness for: \(plan.goal)", toolId: "OutputVerification")

        var issues: [String] = []
        var suggestions: [String] = []

        // Check 1: All steps have results
        for step in plan.steps where step.result == nil {
            issues.append("Step '\(step.description)' has no result")
            suggestions.append("Ensure step was executed")
        }

        // Check 2: No stuck running steps
        for step in plan.steps where step.status == .running {
            issues.append("Step '\(step.description)' is still marked as running")
            suggestions.append("Complete or fail stuck steps before finishing")
        }

        // Check 3: Completed steps must not report failure
        for step in plan.steps where step.status == .completed {
            if let result = step.result, !result.success {
                issues.append("Step '\(step.description)' completed but reports failure: \(result.error ?? "unknown error")")
                suggestions.append("Re-execute step and inspect error output")
            }
        }

        // Check 4: File operations produced real files with real content
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

        // Check 5: No failed steps
        let failedSteps = plan.steps.filter { $0.status == .failed }
        if !failedSteps.isEmpty {
            issues.append("\(failedSteps.count) step(s) failed")
            suggestions.append("Review and retry failed steps")
        }

        // Check 6: Independent compilation verification
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

// MARK: - Content checks (file-private copies of AssistVerificationPipeline helpers)
//
// Legacy defines these as `internal` funcs in Backend/Assist/AssistVerificationPipeline.swift.
// Reproduced here as file-private so this engine does not depend on the (not yet ported)
// verification pipeline. If that pipeline is later ported, delete these copies and use the
// shared helpers.
private func assistContainsPlaceholderToken(_ content: String) -> Bool {
    let tokens = [
        "TODO", "FIXME", "PLACEHOLDER", "STUB",
        "not implemented", "unimplemented",
        "fatalError(\"TODO", "fatalError(\"Stub", "fatalError(\"Not implemented", "fatalError(\"placeholder"
    ]
    return tokens.contains { content.contains($0) }
}

private func assistHasConflictMarkers(_ content: String) -> Bool {
    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<<<<<<<") || trimmed.hasPrefix(">>>>>>>") || trimmed == "=======" {
            return true
        }
    }
    return false
}
