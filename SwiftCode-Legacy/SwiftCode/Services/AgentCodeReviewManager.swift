import Foundation
import SwiftUI

@MainActor
public final class AgentCodeReviewManager: ObservableObject {
    public static let shared = AgentCodeReviewManager()
    private init() {}

    @Published public var currentResult: CodeReviewResult?
    @Published public var reviewResults: [CodeReviewResult] = []
    @Published public var isReviewing = false
    @Published public var errorMessage: String?

    public func reviewCode(code: String, fileName: String) async {
        isReviewing = true
        errorMessage = nil

        // Simulate AI analysis delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Mock result for now, as the actual AI integration would go through OpenRouterService
        let mockIssues = [
            CodeReviewIssue(
                severity: .warning,
                category: .readability,
                lineNumber: 10,
                description: "Method is too long and complex.",
                suggestion: "Consider breaking this method into smaller, more focused functions.",
                codeSnippet: nil
            ),
            CodeReviewIssue(
                severity: .info,
                category: .readability,
                lineNumber: 25,
                description: "Prefer 'let' over 'var' for immutable values.",
                suggestion: "Change 'var' to 'let' for this constant.",
                codeSnippet: "var pi = 3.14"
            )
        ]

        let result = CodeReviewResult(
            fileName: fileName,
            reviewedAt: Date(),
            overallScore: 85,
            summary: "The code is generally well-structured but could benefit from some refactoring to improve readability and maintainability.",
            issues: mockIssues
        )

        currentResult = result
        reviewResults.insert(result, at: 0)
        isReviewing = false
    }

    public func markResolved(_ issue: CodeReviewIssue, in result: CodeReviewResult) {
        guard let resultIndex = reviewResults.firstIndex(where: { $0.id == result.id }) else { return }
        if let issueIndex = reviewResults[resultIndex].issues.firstIndex(where: { $0.id == issue.id }) {
            reviewResults[resultIndex].issues[issueIndex].isResolved = true

            if currentResult?.id == result.id {
                currentResult?.issues[issueIndex].isResolved = true
            }
        }
    }

    public func deleteResult(_ result: CodeReviewResult) {
        reviewResults.removeAll { $0.id == result.id }
        if currentResult?.id == result.id {
            currentResult = nil
        }
    }
}
