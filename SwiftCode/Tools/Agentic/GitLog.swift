import Foundation

public struct GitLogTool {
    public static let identifier = "git_log"

    public func run(repositoryPath: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["log", "--oneline", "-n", "20"],
            workingDirectory: url
        )
        return result.stdout
    }
}
