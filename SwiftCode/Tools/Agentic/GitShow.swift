import Foundation

public struct GitShowTool {
    public static let identifier = "git_show"

    public func run(repositoryPath: String, hash: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["show", hash],
            workingDirectory: url
        )
        return result.stdout
    }
}
