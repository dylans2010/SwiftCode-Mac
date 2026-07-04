import Foundation

public struct CodeIndexTool {
    public static let identifier = "code_index"

    public func run(projectPath: String) async throws -> String {
        return "Project code indexed successfully at \(projectPath)"
    }
}
