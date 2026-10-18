import Foundation

public struct AssistProtocolConformanceListTool: AssistTool {
    public let id = "protocol_conformance_list"
    public let name = "Protocol Conformance List"
    public let description = "Lists every type that declares conformance to a given protocol, with declaration locations."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists conformers of a protocol.",
            properties: [
                "protocol": JSONSchema(type: "string", description: "Protocol name to search conformances for.")
            ],
            required: ["protocol"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let proto = (input["protocol"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !proto.isEmpty else {
            return .failure("Missing required parameter: protocol")
        }
        let root = context.workspaceRoot
        var conformers: [String] = []
        var extensions: [String] = []
        let declPattern = try? NSRegularExpression(pattern: #"^\s*(?:\w+\s+)*(class|struct|enum|actor)\s+([A-Za-z_][\w]*)\s*:[^\{]*\b"# + NSRegularExpression.escapedPattern(for: proto) + #"\b"#)
        let extPattern = try? NSRegularExpression(pattern: #"^\s*extension\s+([A-Za-z_][\w]*)\s*:[^\{]*\b"# + NSRegularExpression.escapedPattern(for: proto) + #"\b"#)
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for (i, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if let m = declPattern?.firstMatch(in: line, range: range),
                   let r = Range(m.range(at: 2), in: line) {
                    conformers.append("\(String(line[r])) — \(rel):\(i + 1)")
                } else if let m = extPattern?.firstMatch(in: line, range: range),
                          let r = Range(m.range(at: 1), in: line) {
                    extensions.append("extension \(String(line[r])) — \(rel):\(i + 1)")
                }
            }
        }
        let all = (conformers + extensions).sorted()
        if all.isEmpty {
            return .success("No conformances to protocol '\(proto)' found.", data: ["protocol": proto, "count": "0"])
        }
        return .success("Conformances to '\(proto)' (\(all.count)):\n" + all.map { "- \($0)" }.joined(separator: "\n"),
                        data: ["protocol": proto, "count": "\(all.count)"])
    }
}
