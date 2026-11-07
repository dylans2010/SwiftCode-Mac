import Foundation
import os

@MainActor
public final class WorkerReviewEngine: Sendable {
    public static let shared = WorkerReviewEngine()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerReviewEngine")

    private init() {}

    public func review(result: WorkerResult, worker: Worker) async -> WorkerReview {
        logger.info("Conducting parent Assist review for worker '\(worker.name)'...")

        var strengths: [String] = []
        var issues: [String] = []
        var recommendedFixes: [String] = []

        if result.tests.allSatisfy({ $0.passed }) && !result.tests.isEmpty {
            strengths.append("All \(result.tests.count) test assertions passed successfully.")
        } else if result.tests.contains(where: { !$0.passed }) {
            issues.append("One or more validation tests failed.")
            recommendedFixes.append("Fix failing test assertions in \(worker.scope).")
        }

        if !result.knownIssues.isEmpty {
            for issue in result.knownIssues {
                issues.append("Unresolved issue: \(issue)")
                recommendedFixes.append("Remediate issue: \(issue)")
            }
        }

        if result.modifiedFiles.isEmpty && result.createdFiles.isEmpty && result.deletedFiles.isEmpty {
            issues.append("No files were modified or created for assigned task.")
            recommendedFixes.append("Re-execute mutation operations for \(worker.scope).")
        } else {
            strengths.append("Modified \(result.modifiedFiles.count) files and created \(result.createdFiles.count) files within scope.")
        }

        let confidence: Double = issues.isEmpty ? 1.0 : max(0.2, 1.0 - (Double(issues.count) * 0.25))
        let status: WorkerReviewState = issues.isEmpty ? .accepted : .repairRequired

        var repairAssignment: WorkerAssignment? = nil
        if status == .repairRequired {
            repairAssignment = WorkerAssignment(
                name: "\(worker.name) (Repair)",
                scope: worker.scope,
                task: "Repair detected issues: " + issues.joined(separator: "; "),
                role: worker.role,
                dependencies: []
            )
        }

        return WorkerReview(
            workerID: worker.id,
            reviewerModel: "Parent Assist Orchestrator",
            timestamp: Date(),
            status: status,
            confidence: confidence,
            strengths: strengths,
            issues: issues,
            recommendedFixes: recommendedFixes,
            repairAssignment: repairAssignment
        )
    }
}
