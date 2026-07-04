import Foundation

public struct DockerBuildTool {
    public static let identifier = "docker_build"

    public func run(path: String, tag: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/docker"),
            arguments: ["build", "-t", tag, path]
        )
        return result.stdout + result.stderr
    }
}
