import Foundation

public struct GitStatusTool {
    public static let identifier = "git_status"

    public func run(repositoryPath: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["status", "--porcelain"],
            workingDirectory: url
        )
        return result.stdout
    }
}
