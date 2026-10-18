//
//  AssistPodfileInspectorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistPodfileInspectorTool: AssistTool {
    public let id = "podfile_inspector"
    public let name = "Podfile & CocoaPods Inspector"
    public let description = "Inspects CocoaPods dependencies, versions, and target configurations in Podfile and Podfile.lock."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits Podfile and Podfile.lock for CocoaPods pod dependencies.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional directory containing Podfile. Defaults to workspace root.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let podfile = root.appendingPathComponent("Podfile")
        let podfileLock = root.appendingPathComponent("Podfile.lock")

        guard FileManager.default.fileExists(atPath: podfile.path) || FileManager.default.fileExists(atPath: podfileLock.path) else {
            return .success("No CocoaPods Podfile or Podfile.lock found in workspace root.")
        }

        var report = "### CocoaPods Project Inspection:\n\n"

        if FileManager.default.fileExists(atPath: podfile.path), let content = try? String(contentsOf: podfile, encoding: .utf8) {
            let podLines = content.components(separatedBy: .newlines).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("pod ") }
            report += "#### Declared Pods in Podfile (\(podLines.count)):\n"
            for p in podLines {
                report += "- `\(p.trimmingCharacters(in: .whitespaces))`\n"
            }
            report += "\n"
        }

        if FileManager.default.fileExists(atPath: podfileLock.path), let lockContent = try? String(contentsOf: podfileLock, encoding: .utf8) {
            let lines = lockContent.components(separatedBy: .newlines)
            var podsSection = false
            var lockedPods: [String] = []

            for line in lines {
                if line.hasPrefix("PODS:") {
                    podsSection = true
                    continue
                } else if podsSection && (!line.hasPrefix("  - ") && !line.hasPrefix("    - ") && !line.trimmingCharacters(in: .whitespaces).isEmpty && !line.hasPrefix(" ")) {
                    break
                }
                if podsSection && line.hasPrefix("  - ") {
                    lockedPods.append(line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- ", with: ""))
                }
            }

            report += "#### Locked Pod Versions (\(lockedPods.count)):\n"
            for p in lockedPods.prefix(20) {
                report += "- `\(p)`\n"
            }
        }

        return .success(report)
    }
}
