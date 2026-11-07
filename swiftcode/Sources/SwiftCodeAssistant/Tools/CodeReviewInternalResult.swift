import Foundation

public struct CodeReviewInternalResult: Codable, Sendable {
    public let status: String
    public let summary: String
    public let strengths: [String]
    public let issues: [String]
    public let recommendedFixes: [String]
    public let userSee: String
    public let confidence: Double
}
