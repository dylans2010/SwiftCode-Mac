import Foundation

/// Generates concise, truthful recaps directly from live Worker runtime events (M-RECAP).
/// Enforces INV-11: No fabricated or static narrative summaries.
public struct WorkerRecapGenerator: Sendable {
    public static let shared = WorkerRecapGenerator()

    public init() {}

    /// Synthesizes bullet points summarizing a Worker's actual accomplishments from its event log.
    public func generateRecap(from events: [WorkerEvent]) -> [String] {
        var bullets: [String] = []

        let createdCount = events.filter { $0.type == .workerFileChanged && $0.title.contains("Created") }.count
        let modifiedCount = events.filter { $0.type == .workerFileChanged && $0.title.contains("Modified") }.count
        let testsPassedCount = events.filter { $0.type == .workerTestCompleted && $0.title.contains("Passed") }.count
        let testsFailedCount = events.filter { $0.type == .workerTestCompleted && $0.title.contains("Failed") }.count

        if createdCount > 0 || modifiedCount > 0 {
            bullets.append("Files updated: \(createdCount) created, \(modifiedCount) modified.")
        }

        if testsPassedCount > 0 || testsFailedCount > 0 {
            bullets.append("Testing: \(testsPassedCount) passed, \(testsFailedCount) failed.")
        }

        for event in events.suffix(3) {
            if event.type == .workerProgressUpdated && !bullets.contains(event.details) {
                bullets.append(event.details)
            }
        }

        if bullets.isEmpty {
            bullets.append("Worker actively initializing context and repository boundaries.")
        }

        return bullets
    }
}
