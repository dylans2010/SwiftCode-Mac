import Foundation

public struct AssistInfoPlistAuditTool: AssistTool {
    public let id = "info_plist_audit"
    public let name = "Info.plist Audit"
    public let description = "Audits Info.plist files for required keys, version-format sanity, and duplicate bundle identifiers."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Audits Info.plist files.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let plists = AssistWorkspaceScan.files(under: root).filter { $0.lastPathComponent == "Info.plist" }
        if plists.isEmpty {
            return .success("No Info.plist files found in the workspace.", data: ["count": "0"])
        }
        let required = ["CFBundleIdentifier", "CFBundleName", "CFBundleShortVersionString", "CFBundleVersion"]
        var bundleIds: [String: [String]] = [:]
        var lines = ["Info.plist audit (\(plists.count) files):"]
        var issueCount = 0
        for url in plists.sorted(by: { $0.path < $1.path }) {
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                lines.append("- \(rel): UNREADABLE plist")
                issueCount += 1
                continue
            }
            var issues: [String] = []
            for key in required where plist[key] == nil {
                issues.append("missing \(key)")
            }
            if let v = plist["CFBundleShortVersionString"] as? String,
               v.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) == nil {
                issues.append("CFBundleShortVersionString '\(v)' is not x.y[.z]")
            }
            if let bid = plist["CFBundleIdentifier"] as? String {
                bundleIds[bid, default: []].append(rel)
            }
            if issues.isEmpty {
                lines.append("- \(rel): OK")
            } else {
                issueCount += issues.count
                lines.append("- \(rel): \(issues.joined(separator: "; "))")
            }
        }
        for (bid, files) in bundleIds where files.count > 1 {
            lines.append("DUPLICATE bundle id '\(bid)' in: \(files.joined(separator: ", "))")
            issueCount += 1
        }
        return .success(lines.joined(separator: "\n"), data: [
            "fileCount": "\(plists.count)", "issueCount": "\(issueCount)"
        ])
    }
}
