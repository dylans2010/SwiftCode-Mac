import Foundation

public struct GitWorktreeTool {
    public static let identifier = "git_worktree"

    public func run(repositoryPath: String, action: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["worktree", action],
            workingDirectory: url
        )
        return result.stdout
    }
}
