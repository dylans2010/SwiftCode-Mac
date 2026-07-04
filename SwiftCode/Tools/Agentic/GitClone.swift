import Foundation

public struct GitCloneTool {
    public static let identifier = "git_clone"

    public func run(remoteURL: String, destinationPath: String) async throws {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["clone", remoteURL, destinationPath]
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }
}
