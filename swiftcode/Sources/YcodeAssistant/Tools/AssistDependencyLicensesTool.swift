import Foundation

public struct AssistDependencyLicensesTool: AssistTool {
    public let id = "dependency_licenses"
    public let name = "Dependency Licenses"
    public let description = "Inventories third-party dependencies from Package.resolved and Podfile.lock, reporting versions for license review."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Inventories dependency licenses.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let fm = FileManager.default
        var rows: [[String]] = []
        let resolved = root.appendingPathComponent("Package.resolved")
        if fm.fileExists(atPath: resolved.path),
           let data = try? Data(contentsOf: resolved),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let pins = (json["pins"] as? [[String: Any]]) ?? (json["object"] as? [String: Any])?["pins"] as? [[String: Any]] ?? []
            for pin in pins {
                let identity = (pin["identity"] as? String) ?? (pin["package"] as? String) ?? "unknown"
                let version = ((pin["state"] as? [String: Any])?["version"] as? String) ?? "unknown"
                rows.append([identity, "SwiftPM", version, "see package repository"])
            }
        }
        let podLock = root.appendingPathComponent("Podfile.lock")
        if fm.fileExists(atPath: podLock.path), let text = try? String(contentsOf: podLock, encoding: .utf8) {
            var inPods = false
            for line in text.components(separatedBy: .newlines) {
                if line == "PODS:" { inPods = true; continue }
                if inPods {
                    if line.isEmpty || !line.hasPrefix(" ") { break }
                    let name = line.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
                    if !name.isEmpty && !name.hasPrefix("-") { rows.append([name, "CocoaPods", "", "see podspec"]) }
                }
            }
        }
        if rows.isEmpty {
            return .success("No resolvable dependency lockfiles found (checked Package.resolved, Podfile.lock).", data: ["count": "0"])
        }
        let table = AssistTextFormat.markdownTable(headers: ["Dependency", "Manager", "Version", "License"], rows: rows)
        return .success("Dependency license inventory:\n\(table)\n\nNote: license text lives in each package's repository; verify before distribution.", data: ["count": "\(rows.count)"])
    }
}
