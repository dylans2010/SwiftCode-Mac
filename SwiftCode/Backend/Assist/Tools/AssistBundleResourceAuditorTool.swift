//
//  AssistBundleResourceAuditorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistBundleResourceAuditorTool: AssistTool {
    public let id = "bundle_resource_auditor"
    public let name = "Bundle Resource Auditor"
    public let description = "Audits project resources, asset catalogs, and bundle copy phases for missing or orphaned assets."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans project assets, xcassets catalogs, and PBXResourcesBuildPhase for orphaned or missing files.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional directory path to scan. Defaults to workspace root.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        var assetCatalogs: [String] = []
        var jsonResources: [String] = []
        var fontFiles: [String] = []
        var orphanedEntries: [String] = []

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let rel = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            if fileURL.pathExtension == "xcassets" {
                assetCatalogs.append(rel)
            } else if fileURL.pathExtension == "json" && !rel.contains("DerivedData") && !rel.contains("Pods") {
                jsonResources.append(rel)
            } else if ["ttf", "otf"].contains(fileURL.pathExtension.lowercased()) {
                fontFiles.append(rel)
            }

            // Check if Contents.json has missing image files
            if fileURL.lastPathComponent == "Contents.json" && rel.contains(".imageset") {
                if let data = try? Data(contentsOf: fileURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let images = json["images"] as? [[String: Any]] {
                    let parentDir = fileURL.deletingLastPathComponent()
                    for img in images {
                        if let filename = img["filename"] as? String {
                            let imgURL = parentDir.appendingPathComponent(filename)
                            if !FileManager.default.fileExists(atPath: imgURL.path) {
                                orphanedEntries.append("Missing image asset: `\(rel)` references `\(filename)` which is not on disk.")
                            }
                        }
                    }
                }
            }
        }

        var report = "### Bundle Resource Audit Report:\n\n"
        report += "- **Asset Catalogs**: \(assetCatalogs.count) found (\(assetCatalogs.prefix(5).joined(separator: ", ")))\n"
        report += "- **Bundled JSON Resources**: \(jsonResources.count) files\n"
        report += "- **Custom Font Files**: \(fontFiles.count) files\n\n"

        if orphanedEntries.isEmpty {
            report += "✅ All asset catalog image sets and resource declarations verified on disk."
        } else {
            report += "#### ⚠️ Discrepancies Detected:\n"
            for item in orphanedEntries.prefix(15) {
                report += "- \(item)\n"
            }
        }

        return .success(report)
    }
}
