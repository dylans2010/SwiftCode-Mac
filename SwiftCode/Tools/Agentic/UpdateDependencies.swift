import Foundation

public struct UpdateDependenciesTool {
    public static let identifier = "update_dependencies"

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["package", "update"],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
