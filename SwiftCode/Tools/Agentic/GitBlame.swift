import Foundation

public struct GitBlameTool {
    public static let identifier = "git_blame"

    public func run(repositoryPath: String, file: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["blame", file],
            workingDirectory: url
        )
        return result.stdout
    }
}
