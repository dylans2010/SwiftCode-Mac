import Foundation

public struct GrepTool {
    public static let identifier = "grep"

    public func run(pattern: String, directory: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/grep"),
            arguments: ["-r", "-n", pattern, directory]
        )
        return result.stdout
    }
}
