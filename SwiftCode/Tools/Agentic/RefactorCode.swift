import Foundation

public struct RefactorCodeTool {
    public static let identifier = "refactor_code"

    public func run(code: String, instructions: String) async throws -> String {
        return "// Refactored code\n\(code)"
    }
}
