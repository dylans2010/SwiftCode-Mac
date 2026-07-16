import Foundation

/// Generates recovery strategies for failed operations
public final class AssistRecoveryStrategyGenerator {
    private let context: AssistContext

    public struct RecoveryStrategy {
        let approach: RecoveryApproach
        let steps: [String]
        let estimatedSuccess: Double // 0.0 to 1.0
    }

    public enum RecoveryApproach {
        case retry
        case alternateMethod
        case simplifyOperation
        case skipAndContinue
        case requireIntervention
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Generates a recovery strategy based on root cause analysis
    public func generateStrategy(
        rootCause: AssistFailureRootCauseAnalyzer.RootCauseAnalysis,
        failedStep: AssistExecutionStep
    ) async -> RecoveryStrategy {
        await context.logger.info("Generating recovery strategy for: \(rootCause.primaryCause)", toolId: "RecoveryStrategy")

        // Select strategy based on root cause
        switch rootCause.primaryCause {
        case let cause where cause.contains("Missing file"):
            return RecoveryStrategy(
                approach: .alternateMethod,
                steps: [
                    "Create the missing file automatically",
                    "Populate with default content",
                    "Retry the original operation"
                ],
                estimatedSuccess: 0.9
            )

        case let cause where cause.contains("Permission"):
            return RecoveryStrategy(
                approach: .requireIntervention,
                steps: [
                    "Request user to grant necessary permissions",
                    "Retry after permission grant"
                ],
                estimatedSuccess: 0.5
            )

        case let cause where cause.contains("syntax error"):
            return RecoveryStrategy(
                approach: .alternateMethod,
                steps: [
                    "Use automated repair tool",
                    "Apply syntax fixes",
                    "Validate corrected code"
                ],
                estimatedSuccess: 0.8
            )

        case let cause where cause.contains("timeout"):
            return RecoveryStrategy(
                approach: .simplifyOperation,
                steps: [
                    "Break operation into smaller chunks",
                    "Execute incrementally",
                    "Combine results"
                ],
                estimatedSuccess: 0.7
            )

        case let cause where cause.contains("Network"):
            return RecoveryStrategy(
                approach: .retry,
                steps: [
                    "Wait briefly",
                    "Retry operation with exponential backoff"
                ],
                estimatedSuccess: 0.6
            )

        default:
            return RecoveryStrategy(
                approach: .retry,
                steps: [
                    "Retry operation once",
                    "If still fails, skip and continue"
                ],
                estimatedSuccess: 0.4
            )
        }
    }
}
