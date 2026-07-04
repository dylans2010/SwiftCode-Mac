import Foundation

public struct FixBugsTool {
    public static let identifier = "fix_bugs"

    public func run(code: String, issue: String) async throws -> String {
        return "// Fixed code\n\(code)"
    }
}
