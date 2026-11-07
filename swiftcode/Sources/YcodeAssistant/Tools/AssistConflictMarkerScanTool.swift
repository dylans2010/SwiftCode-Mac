import Foundation

public struct AssistConflictMarkerScanTool: AssistTool {
    public let id = "conflict_marker_scan"
    public let name = "Conflict Marker Scan"
    public let description = "Scans source files for unresolved merge-conflict markers (<<<<<<<, =======, >>>>>>>)."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans for merge-conflict markers.",
            properties: [
                "limit": JSONSchema(type: "integer", description: "Maximum files to report. Default 50.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let limit = max(1, min(500, (input["limit"] as? Int) ?? 50))
        let root = context.workspaceRoot
        var hits: [(String, [Int])] = []
        for url in AssistWorkspaceScan.files(under: root, extensions: AssistWorkspaceScan.sourceExts) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            var markerLines: [Int] = []
            for (i, line) in lines.enumerated() {
                if line.hasPrefix("<<<<<<<") || line.hasPrefix("=======") || line.hasPrefix(">>>>>>>") {
                    markerLines.append(i + 1)
                }
            }
            if !markerLines.isEmpty {
                hits.append((AssistWorkspacePaths.relative(url, workspaceRoot: root), markerLines))
                if hits.count >= limit { break }
            }
        }
        if hits.isEmpty {
            return .success("No merge-conflict markers found in source files.", data: ["fileCount": "0"])
        }
        var lines = ["Files with unresolved conflict markers (\(hits.count)):"]
        for (path, nums) in hits.sorted(by: { $0.0 < $1.0 }) {
            lines.append("- \(path): lines \(nums.prefix(10).map(String.init).joined(separator: ", "))")
        }
        return .success(lines.joined(separator: "\n"), data: ["fileCount": "\(hits.count)"])
    }
}
