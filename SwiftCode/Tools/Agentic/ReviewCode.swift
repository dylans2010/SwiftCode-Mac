import Foundation

public struct ReviewCodeTool {
    public static let identifier = "review_code"

    public func run(code: String) async throws -> String {
        return "Review comments: LGTM!"
    }
}
