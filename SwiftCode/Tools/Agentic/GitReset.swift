import Foundation

public struct GitResetTool {
    public static let identifier = "git_reset"

    public func run(repositoryPath: String, mode: String = "--hard", target: String = "HEAD") async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["reset", mode, target],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }
}
