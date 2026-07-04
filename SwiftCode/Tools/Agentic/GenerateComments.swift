import Foundation

public struct GenerateCommentsTool {
    public static let identifier = "generate_comments"

    public func run(code: String) async throws -> String {
        return "// Comments for the provided code"
    }
}
