import Foundation

public struct DockerRunTool {
    public static let identifier = "docker_run"

    public func run(image: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/docker"),
            arguments: ["run", image]
        )
        return result.stdout + result.stderr
    }
}
