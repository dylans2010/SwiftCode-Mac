// STAGED PORT — SwiftCode-Legacy `Backend/Assist/Assist Frameworks/AssistFailureRootCauseAnalyzer.swift`
// (Legacy main d51a8f0d; Dylan's own code, direct port authorised under MIT).
// Target: SwiftCodeAssistant. Body is Legacy verbatim unless noted below.
// Dependency of _AssistCriticalAutonomousEngine (root-cause phase). Ledger marks this file SUPERSEDED by SwiftCodeMCP/Tools/SwiftCodeTools+Planning.swift, but that is an MCP tool surface in SwiftCodeMCP — a module SwiftCodeAssistant cannot import — and it exposes no AssistFailureRootCauseAnalyzer class API; the staged autonomous engine calls analyze(step:) -> RootCauseAnalysis. Ported so the engine's own subsystem layer exists in its own target, not as a competing MCP implementation.
// Remaining deps (now staged in AssistModels.swift by the parallel port — see _notes/agent-models-decisions.md): AssistContext (logger), AssistExecutionStep (+ .result?.error).

import Foundation

/// Analyzes failures to determine root causes for better recovery
@MainActor
public final class AssistFailureRootCauseAnalyzer {
    private let context: AssistContext

    public struct RootCauseAnalysis {
        let primaryCause: String
        let contributingFactors: [String]
        let suggestedFixes: [String]
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Analyzes a failed step to determine root cause
    public func analyze(step: AssistExecutionStep) async -> RootCauseAnalysis {
        await context.logger.info("Analyzing failure for step: \(step.toolId)", toolId: "RootCauseAnalyzer")

        let errorMessage = step.result?.error ?? "Unknown error"

        var primaryCause = "Unknown failure"
        var contributingFactors: [String] = []
        var suggestedFixes: [String] = []

        // Pattern matching for common error types
        if errorMessage.contains("file not found") || errorMessage.contains("does not exist") {
            primaryCause = "Missing file or directory"
            contributingFactors.append("File path may be incorrect")
            suggestedFixes.append("Verify file path exists")
            suggestedFixes.append("Create missing file or directory")
        } else if errorMessage.contains("permission denied") || errorMessage.contains("not allowed") {
            primaryCause = "Permission or access error"
            contributingFactors.append("Insufficient permissions")
            suggestedFixes.append("Check file permissions")
            suggestedFixes.append("Verify workspace access")
        } else if errorMessage.contains("syntax error") || errorMessage.contains("invalid syntax") {
            primaryCause = "Code syntax error"
            contributingFactors.append("Generated code has syntax issues")
            suggestedFixes.append("Review and fix syntax errors")
            suggestedFixes.append("Use formatter tool")
        } else if errorMessage.contains("timeout") || errorMessage.contains("timed out") {
            primaryCause = "Operation timeout"
            contributingFactors.append("Operation took too long")
            suggestedFixes.append("Retry with increased timeout")
            suggestedFixes.append("Break into smaller operations")
        } else if errorMessage.contains("network") || errorMessage.contains("connection") {
            primaryCause = "Network or connectivity issue"
            contributingFactors.append("External service unavailable")
            suggestedFixes.append("Retry operation")
            suggestedFixes.append("Check network connectivity")
        }

        return RootCauseAnalysis(
            primaryCause: primaryCause,
            contributingFactors: contributingFactors,
            suggestedFixes: suggestedFixes
        )
    }
}
