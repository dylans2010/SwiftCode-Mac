import Foundation

public struct ViewContainerLogsTool {
    public static let identifier = "view_container_logs"

    public func run(containerID: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/docker"),
            arguments: ["logs", containerID]
        )
        return result.stdout + result.stderr
    }
}
