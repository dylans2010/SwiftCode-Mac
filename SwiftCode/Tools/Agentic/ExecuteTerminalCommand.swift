import Foundation

public struct ExecuteTerminalCommandTool {
    public static let identifier = "execute_terminal_command"

    public func run(command: String, workingDirectory: String? = nil) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let workingDir = workingDirectory != nil ? URL(fileURLWithPath: workingDirectory!) : nil
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command],
            workingDirectory: workingDir
        )
        return (result.stdout, result.stderr, result.exitCode)
    }
}
