import Foundation

/// Detects context drift from original objectives
@MainActor
public final class AssistContextDriftDetector {
    private let context: AssistContext

    private static let engineeringVerbs: Set<String> = [
        "test", "tests", "testing", "verify", "lint", "document", "documentation",
        "error", "guard", "robust", "refactor", "benchmark", "spec", "clean",
        "fix", "implement", "validate", "coverage", "harden", "edge"
    ]

    public struct DriftAnalysis {
        let hasDrift: Bool
        let driftScore: Double // 0.0 to 1.0
        let reason: String

        var isSevere: Bool { driftScore > 0.8 }
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Analyzes if current execution has drifted from original goal
    public func detectDrift(
        originalGoal: String,
        currentGoal: String,
        completedTasks: [String]
    ) async -> DriftAnalysis {
        await context.logger.info("Analyzing context drift", toolId: "DriftDetector")

        // Anchor on the original goal plus everything already completed so that
        // legitimate follow-up goals (tests, docs, hardening) are not flagged.
        let anchorKeywords = Set(extractKeywords(from: ([originalGoal] + completedTasks).joined(separator: " ")))
        let currentKeywords = Set(extractKeywords(from: currentGoal))
        let relatedKeywords = currentKeywords.intersection(anchorKeywords)

        let coverage = currentKeywords.isEmpty ? 1.0 : Double(relatedKeywords.count) / Double(currentKeywords.count)
        let hasEngineeringLink = currentKeywords.contains { Self.engineeringVerbs.contains($0) }

        let isAligned = coverage >= 0.2 || hasEngineeringLink
        let driftScore = isAligned ? (1.0 - coverage) * 0.5 : 0.9

        let hasDrift = driftScore > 0.6 // More than 60% drift

        let reason: String
        if driftScore > 0.8 {
            reason = "Current goal has significantly diverged from original objective"
        } else if hasDrift {
            reason = "Moderate drift detected, but still aligned with original goal"
        } else {
            reason = "No significant drift detected"
        }

        if hasDrift {
            await context.logger.warning("Context drift detected: \(reason)", toolId: "DriftDetector")
        }

        return DriftAnalysis(hasDrift: hasDrift, driftScore: driftScore, reason: reason)
    }

    private func extractKeywords(from text: String) -> [String] {
        let lowercased = text.lowercased()
        // Remove common words
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "for", "to", "of", "in", "on", "at", "from"])
        let words = lowercased.components(separatedBy: .whitespacesAndNewlines)
            .filter { !stopWords.contains($0) && $0.count > 2 }
        return words
    }
}
