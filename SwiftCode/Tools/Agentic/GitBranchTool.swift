import Foundation

public struct GitBranchTool {
    public static let identifier = "git_branch"

    public func run(repositoryPath: String) async throws -> [String] {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["branch", "--format=%(refname:short)"],
            workingDirectory: url
        )
        return result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
}
