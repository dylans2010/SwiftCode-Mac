import Foundation

public struct DockerComposeTool {
    public static let identifier = "docker_compose"

    public func run(path: String, action: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/docker-compose"),
            arguments: ["-f", path, action]
        )
        return result.stdout + result.stderr
    }
}
