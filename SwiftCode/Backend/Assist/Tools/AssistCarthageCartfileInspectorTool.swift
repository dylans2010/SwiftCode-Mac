//
//  AssistCarthageCartfileInspectorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistCarthageCartfileInspectorTool: AssistTool {
    public let id = "carthage_cartfile_inspector"
    public let name = "Carthage Cartfile Inspector"
    public let description = "Inspects Carthage dependencies and resolved versions in Cartfile and Cartfile.resolved."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans for Cartfile and Cartfile.resolved in the workspace.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let cartfile = root.appendingPathComponent("Cartfile")
        let cartfileResolved = root.appendingPathComponent("Cartfile.resolved")

        guard FileManager.default.fileExists(atPath: cartfile.path) || FileManager.default.fileExists(atPath: cartfileResolved.path) else {
            return .success("No Carthage Cartfile or Cartfile.resolved found in workspace root.")
        }

        var report = "### Carthage Dependencies Report:\n\n"

        if FileManager.default.fileExists(atPath: cartfile.path), let c = try? String(contentsOf: cartfile, encoding: .utf8) {
            let lines = c.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
            report += "#### Declared in Cartfile:\n"
            for l in lines {
                report += "- `\(l)`\n"
            }
            report += "\n"
        }

        if FileManager.default.fileExists(atPath: cartfileResolved.path), let r = try? String(contentsOf: cartfileResolved, encoding: .utf8) {
            let lines = r.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            report += "#### Resolved in Cartfile.resolved:\n"
            for l in lines {
                report += "- `\(l)`\n"
            }
        }

        return .success(report)
    }
}
