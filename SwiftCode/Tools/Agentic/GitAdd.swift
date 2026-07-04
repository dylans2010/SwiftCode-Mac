import Foundation

public struct GitAddTool {
    public static let identifier = "git_add"

    public func run(repositoryPath: String, files: [String]) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["add"] + files,
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }
}
