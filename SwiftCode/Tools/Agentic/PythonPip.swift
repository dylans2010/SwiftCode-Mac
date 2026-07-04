import Foundation

public struct PythonPipTool {
    public static let identifier = "python_pip"

    public func run(action: String, package: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/pip"),
            arguments: [action, package]
        )
        return result.stdout + result.stderr
    }
}
