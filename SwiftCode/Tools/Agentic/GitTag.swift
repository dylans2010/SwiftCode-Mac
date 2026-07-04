import Foundation

public struct GitTagTool {
    public static let identifier = "git_tag"

    public func run(repositoryPath: String) async throws -> [String] {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["tag"],
            workingDirectory: url
        )
        return result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
}
