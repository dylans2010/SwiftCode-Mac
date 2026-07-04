import Foundation

public struct GitDiffTool {
    public static let identifier = "git_diff"

    public func run(repositoryPath: String, file: String? = nil) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        var args = ["diff"]
        if let file = file { args.append(file) }
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: args,
            workingDirectory: url
        )
        return result.stdout
    }
}
