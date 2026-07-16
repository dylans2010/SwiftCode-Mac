import Foundation

/// Detects context drift from original objectives
public final class AssistContextDriftDetector {
    private let context: AssistContext

    public struct DriftAnalysis {
        let hasDrift: Bool
        let driftScore: Double // 0.0 to 1.0
        let reason: String
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

        // Simple keyword-based drift detection
        let originalKeywords = extractKeywords(from: originalGoal)
        let currentKeywords = extractKeywords(from: currentGoal)

        let commonKeywords = Set(originalKeywords).intersection(Set(currentKeywords))
        let totalKeywords = Set(originalKeywords).union(Set(currentKeywords))

        let similarity = totalKeywords.isEmpty ? 0 : Double(commonKeywords.count) / Double(totalKeywords.count)
        let driftScore = 1.0 - similarity

        let hasDrift = driftScore > 0.6 // More than 60% drift

        let reason: String
        if hasDrift {
            reason = "Current goal has significantly diverged from original objective"
        } else if driftScore > 0.3 {
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
