//
//  AssistFrameworkLinkerAuditorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistFrameworkLinkerAuditorTool: AssistTool {
    public let id = "framework_linker_auditor"
    public let name = "Framework Linker Auditor"
    public let description = "Inspects PBXFrameworksBuildPhase in Xcode projects to audit linked system and dynamic frameworks."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans project.pbxproj to identify all frameworks in the PBXFrameworksBuildPhase.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional path to .xcodeproj. Defaults to workspace root.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        var pbxURL: URL?

        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == "project.pbxproj" {
                pbxURL = item
                break
            }
        }

        guard let targetPBX = pbxURL, let text = try? String(contentsOf: targetPBX, encoding: .utf8) else {
            return .success("No project.pbxproj file found in workspace.")
        }

        var linkedFrameworks: [String] = []
        let lines = text.components(separatedBy: .newlines)
        var inFrameworksPhase = false

        for line in lines {
            if line.contains("/* Frameworks */ = {") || line.contains("isa = PBXFrameworksBuildPhase;") {
                inFrameworksPhase = true
            } else if inFrameworksPhase && line.contains("};") {
                inFrameworksPhase = false
            } else if inFrameworksPhase {
                // Example: 75E911022EB7466700BEA120 /* WelcomeView in Frameworks */ = {isa = PBXBuildFile; ...
                if let start = line.range(of: "/* "), let end = line.range(of: " in Frameworks */") {
                    let name = String(line[start.upperBound..<end.lowerBound])
                    linkedFrameworks.append(name)
                }
            }
        }

        var report = "### Framework Linker Audit (`\(targetPBX.deletingLastPathComponent().lastPathComponent)`):\n\n"
        if linkedFrameworks.isEmpty {
            report += "No frameworks explicitly linked in PBXFrameworksBuildPhase (e.g. Pure SPM or auto-linked modules).\n"
        } else {
            report += "#### Linked Frameworks & Dependencies (\(linkedFrameworks.count)):\n"
            for f in linkedFrameworks {
                report += "- `\(f)`\n"
            }
        }

        return .success(report)
    }
}
