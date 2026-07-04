import Foundation

public struct GitRebaseTool {
    public static let identifier = "git_rebase"

    public func run(repositoryPath: String, branch: String) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["rebase", branch],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }
}
