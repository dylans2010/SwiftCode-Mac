import Foundation

public struct ExecuteTerminalCommandTool: AgentTool {
    public static let identifier = "execute_terminal_command"
    public let name = "execute_terminal_command"
    public let description = "Executes a terminal command in a given working directory."
    public let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "command": ["type": "string"],
            "workingDirectory": ["type": "string"]
        ],
        "required": ["command"]
    ]

    public func run(command: String, workingDirectory: String? = nil) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let workingDir = workingDirectory != nil ? URL(fileURLWithPath: workingDirectory!) : nil
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command],
            workingDirectory: workingDir
        )
        return (result.stdout, result.stderr, result.exitCode)
    }

    public func execute(arguments: [String: Any]) async throws -> String {
        guard let command = arguments["command"] as? String else { throw AgentError.toolError("Missing command") }
        let workingDirectory = arguments["workingDirectory"] as? String
        let result = try await run(command: command, workingDirectory: workingDirectory)

        if result.exitCode == 0 {
            return result.stdout
        } else {
            return "Command failed with exit code \(result.exitCode)\n\nSTDOUT: \(result.stdout)\n\nSTDERR: \(result.stderr)"
        }
    }
}
