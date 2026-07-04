import Foundation

public struct RunBuildTool {
    public static let identifier = "run_build"

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["build"],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
