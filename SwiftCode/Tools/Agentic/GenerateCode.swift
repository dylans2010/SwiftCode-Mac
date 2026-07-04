import Foundation

public struct GenerateCodeTool {
    public static let identifier = "generate_code"

    public func run(prompt: String) async throws -> String {
        return "// Generated code based on: \(prompt)\nfunc generated() {}"
    }
}
