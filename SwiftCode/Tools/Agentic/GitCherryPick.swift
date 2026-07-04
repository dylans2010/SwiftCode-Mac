import Foundation

public struct GitCherryPickTool {
    public static let identifier = "git_cherry_pick"

    public func run(repositoryPath: String, hash: String) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["cherry-pick", hash],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }
}
