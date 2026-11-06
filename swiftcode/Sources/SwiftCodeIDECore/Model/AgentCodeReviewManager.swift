import Foundation

/// Results store for code reviews (Legacy
/// `SwiftCode/Features/AI/AgentCodeReviewManager.swift`, Dylan's own
/// code, ported under MIT).
///
/// Legacy's `reviewCode` was a mock (a 2-second sleep returning
/// hardcoded issues) and is deliberately NOT ported — a mock reviewer
/// would be fake data. The real reviewer is the MCP `code_review`
/// tool, which returns `CodeReviewResult` values; this manager is the
/// store those results land in, with the same resolution / deletion
/// behaviour Legacy had. `isReviewing` is set by the caller while a
/// real review runs.
///
/// Wiring: no lifecycle hook — a shared observable object the
/// editor creates on demand. The review UI calls `addResult(_:)`
/// with the tool's result, `markResolved(_:)` / `deleteResult(_:)`
/// from the results list.
@MainActor
public final class AgentCodeReviewManager: ObservableObject {
    public static let shared = AgentCodeReviewManager()

    @Published public var reviewResults: [CodeReviewResult] = []
    @Published public var isReviewing = false
    @Published public var currentResult: CodeReviewResult?

    public init() {}

    public func addResult(_ result: CodeReviewResult) {
        reviewResults.append(result)
        currentResult = result
    }

    public func markResolved(_ issue: CodeReviewIssue) {
        for resultIndex in reviewResults.indices {
            guard let issueIndex = reviewResults[resultIndex].issues.firstIndex(where: { $0.id == issue.id }) else { continue }
            reviewResults[resultIndex].issues[issueIndex].isResolved = true
            return
        }
    }

    public func deleteResult(_ result: CodeReviewResult) {
        reviewResults.removeAll { $0.id == result.id }
        if currentResult?.id == result.id { currentResult = reviewResults.last }
    }
}
