import Foundation

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
