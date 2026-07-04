import Foundation

public struct GlobSearchTool {
    public static let identifier = "glob_search"

    public func run(pattern: String) async throws -> [String] {
        // Simple implementation using find command
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/find"),
            arguments: [".", "-name", pattern]
        )
        return result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
}
