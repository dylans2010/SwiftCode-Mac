//
//  AssistSPMDependencyTreeTool.swift
//  SwiftCode
//

import Foundation

public struct AssistSPMDependencyTreeTool: AssistTool {
    public let id = "spm_dependency_tree"
    public let name = "SPM Dependency Tree"
    public let description = "Parses Package.resolved and Package.swift to construct the complete resolved dependency tree."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Parses Swift Package Manager lockfiles (Package.resolved) to show packages, versions, and git revisions.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional explicit path to Package.resolved. If omitted, workspace is searched.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        var resolvedURL: URL?

        if let explicit = input["path"] as? String, !explicit.isEmpty {
            resolvedURL = explicit.hasPrefix("/") ? URL(fileURLWithPath: explicit) : root.appendingPathComponent(explicit)
        } else {
            let candidates = [
                root.appendingPathComponent("Package.resolved"),
                root.appendingPathComponent(".swiftpm/xcode/package.resolved"),
                root.appendingPathComponent("SwiftCode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
            ]
            for c in candidates {
                if FileManager.default.fileExists(atPath: c.path) {
                    resolvedURL = c
                    break
                }
            }
            if resolvedURL == nil {
                let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let item = enumerator?.nextObject() as? URL {
                    if item.lastPathComponent.lowercased() == "package.resolved" {
                        resolvedURL = item
                        break
                    }
                }
            }
        }

        guard let targetFile = resolvedURL, FileManager.default.fileExists(atPath: targetFile.path),
              let data = try? Data(contentsOf: targetFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .success("No Package.resolved file found in workspace.")
        }

        var pinsList: [(identity: String, location: String, version: String, revision: String)] = []

        // Format v2/v3 has "pins": [ { "identity", "location", "state": { "version", "revision" } } ]
        if let pins = json["pins"] as? [[String: Any]] {
            for p in pins {
                let id = p["identity"] as? String ?? (p["package"] as? String ?? "unknown")
                let loc = p["location"] as? String ?? (p["repositoryURL"] as? String ?? "")
                let state = p["state"] as? [String: Any] ?? [:]
                let ver = state["version"] as? String ?? "unversioned"
                let rev = String((state["revision"] as? String ?? "").prefix(8))
                pinsList.append((id, loc, ver, rev))
            }
        } else if let object = json["object"] as? [String: Any], let pins = object["pins"] as? [[String: Any]] {
            for p in pins {
                let id = p["package"] as? String ?? "unknown"
                let loc = p["repositoryURL"] as? String ?? ""
                let state = p["state"] as? [String: Any] ?? [:]
                let ver = state["version"] as? String ?? "unversioned"
                let rev = String((state["revision"] as? String ?? "").prefix(8))
                pinsList.append((id, loc, ver, rev))
            }
        }

        var report = "### SPM Dependency Tree (`\(targetFile.path.replacingOccurrences(of: root.path + "/", with: ""))`):\n\n"
        report += "- **Total Resolved Packages**: \(pinsList.count)\n\n"

        for p in pinsList.sorted(by: { $0.identity < $1.identity }) {
            report += "- **\(p.identity)** @ `\(p.version)` (\(p.revision))\n  - URL: `\(p.location)`\n"
        }

        return .success(report)
    }
}
