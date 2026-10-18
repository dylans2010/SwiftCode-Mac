import Foundation

public struct AssistListArtifactsTool: AssistTool {
    public let id = "list_artifacts"
    public let name = "List Artifacts"
    public let description = "Lists all Markdown artifacts in the native artifact store, including agent_notes.md, newest first."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Lists artifacts.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let records = AssistArtifactStore.shared.listArtifacts(workspaceRoot: context.workspaceRoot)
        if records.isEmpty {
            return .success("No artifacts yet. Use create_artifact to produce the first one.", data: ["count": "0"])
        }
        var lines = ["Artifacts (\(records.count)):"]
        for r in records {
            let desc = r.description.isEmpty ? "" : " — \(r.description.prefix(100))"
            lines.append("- \(r.title) [\(r.kind.displayName)] — \(r.relativePath)\(desc)")
        }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(records.count)"])
    }
}
