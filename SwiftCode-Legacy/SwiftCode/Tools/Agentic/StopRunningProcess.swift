import Foundation

public struct StopRunningProcessTool: AgentTool {
    public static let identifier = "stop_running_process"
    public let name = "stop_running_process"
    public let description = "Stops a running process using its PID."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "pid": ["type": "integer"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["pid"]
    ]

    public func run(pid: Int32) async throws {
        kill(pid, SIGTERM)
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let pid = arguments["pid"] as? Int32 else {
            throw AgentError.toolError("Missing pid")
        }
        try await run(pid: pid)
        return "Process \(pid) terminated."
    }
}
