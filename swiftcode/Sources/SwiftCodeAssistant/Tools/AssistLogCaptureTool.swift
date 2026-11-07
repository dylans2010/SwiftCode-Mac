import Foundation

public struct AssistLogCaptureTool: AssistTool {
    public let id = "env_capture_logs"
    public let name = "Capture Logs"
    public let description = "Captures logs from the execution environment."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Captures recent log lines from the execution environment snapshot history.",
            properties: [
                "memoryKey": JSONSchema(type: "string", description: "Optional memory key whose stored value is included as context. Default: \"\".")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let snapshots = (try? AssistSnapshotFunctions.listSnapshots().prefix(10)) ?? []
        let logLines = snapshots.map { "\($0.timestamp): \($0.message) [\($0.id)]" }
        let memoryPreview = context.memory.retrieve(key: input["memoryKey"] as? String ?? "") ?? ""
        var logs = logLines.joined(separator: "\n")
        if !memoryPreview.isEmpty {
            logs += "\nMemory: \(memoryPreview.prefix(500))"
        }
        if logs.isEmpty {
            logs = "No logs found in snapshot history."
        }
        return .success("Logs captured", data: ["logs": logs])
    }
}
