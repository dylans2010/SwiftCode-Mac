import Foundation

public struct GitStashTool {
    public static let identifier = "git_stash"

    public func run(repositoryPath: String, action: String = "push") async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["stash", action],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }
}
