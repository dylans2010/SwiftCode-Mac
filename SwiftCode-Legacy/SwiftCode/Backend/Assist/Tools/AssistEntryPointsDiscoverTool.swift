import Foundation

public struct AssistEntryPointsDiscoverTool: AssistTool {
    public let id = "entry_points_discover"
    public let name = "Discover Entry Points"
    public let description = "Finds application entry points: @main types, main.swift, and AppDelegate/SceneDelegate classes."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Discovers application entry points.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        var hits: [String] = []
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            if url.lastPathComponent == "main.swift" {
                hits.append("\(rel): main.swift")
                continue
            }
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("@main") {
                    let next = lines.dropFirst(i + 1).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                    hits.append("\(rel):\(i + 1): @main \(next.trimmingCharacters(in: .whitespaces).prefix(80))")
                } else if t.contains("class AppDelegate") || t.contains("class SceneDelegate") {
                    hits.append("\(rel):\(i + 1): \(t.prefix(100))")
                }
            }
            if hits.count > 200 { break }
        }
        if hits.isEmpty {
            return .success("No application entry points discovered (@main, main.swift, AppDelegate).", data: ["count": "0"])
        }
        return .success("Entry points:\n" + hits.sorted().joined(separator: "\n"), data: ["count": "\(hits.count)"])
    }
}
