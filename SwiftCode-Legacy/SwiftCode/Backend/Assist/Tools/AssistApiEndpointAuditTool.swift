import Foundation

public struct AssistApiEndpointAuditTool: AssistTool {
    public let id = "api_endpoint_audit"
    public let name = "API Endpoint Audit"
    public let description = "Inventories hardcoded http(s) URL literals in Swift sources, grouped by host — surfacing endpoints that should be configurable."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits hardcoded URL endpoints.",
            properties: [
                "limit": JSONSchema(type: "integer", description: "Maximum URL sites. Default 100, max 500.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let limit = max(1, min(500, (input["limit"] as? Int) ?? 100))
        let root = context.workspaceRoot
        let urlPattern = try? NSRegularExpression(pattern: #""(https?://[^"\s\\]+)""#)
        var byHost: [String: Int] = [:]
        var sites: [String] = []
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { continue }
                guard let matches = urlPattern?.matches(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
                for m in matches {
                    guard let r = Range(m.range(at: 1), in: line) else { continue }
                    let urlString = String(line[r])
                    let host = URL(string: urlString)?.host ?? "(unparseable)"
                    // Skip documentation/example hosts.
                    if host.contains("example.") || host.contains("apple.com") && urlString.contains("developer") { continue }
                    byHost[host, default: 0] += 1
                    if sites.count < limit {
                        sites.append("\(rel):\(i + 1): \(urlString.prefix(100))")
                    }
                }
            }
        }
        if sites.isEmpty {
            return .success("No hardcoded http(s) endpoints found in Swift sources.", data: ["count": "0"])
        }
        var lines = ["Hardcoded endpoints by host:"]
        for (host, count) in byHost.sorted(by: { $0.value > $1.value }) {
            lines.append("- \(host): \(count)")
        }
        lines.append("Sites (\(sites.count)\(sites.count >= limit ? "+" : "")):")
        lines += sites.map { "- \($0)" }
        return .success(lines.joined(separator: "\n"), data: ["hostCount": "\(byHost.count)", "siteCount": "\(sites.count)"])
    }
}
