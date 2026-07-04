import Foundation

public struct GitRevertTool {
    public static let identifier = "git_revert"

    public func run(repositoryPath: String, hash: String) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["revert", "--no-edit", hash],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }
}
