//
//  AssistProvisioningProfileReaderTool.swift
//  SwiftCode
//

import Foundation

public struct AssistProvisioningProfileReaderTool: AssistTool {
    public let id = "provisioning_profile_reader"
    public let name = "Provisioning Profile Reader"
    public let description = "Decodes and inspects entitlements, team ID, and expiration date of Apple provisioning profiles."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Decodes a .mobileprovision or .provisionprofile file using security cms -D to inspect entitlements and team identifiers.",
            properties: [
                "path": JSONSchema(type: "string", description: "Path to .mobileprovision or .provisionprofile file.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        let resolvedURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : context.workspaceRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return .failure("Provisioning profile not found at: \(resolvedURL.path)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["cms", "-D", "-i", resolvedURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                return .failure("Failed to decode XML property list from provisioning profile.")
            }

            let name = plist["Name"] as? String ?? "Unknown"
            let appIDName = plist["AppIDName"] as? String ?? "Unknown"
            let teamName = plist["TeamName"] as? String ?? "Unknown"
            let teamID = (plist["TeamIdentifier"] as? [String])?.first ?? "Unknown"
            let expiration = plist["ExpirationDate"] as? Date
            let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]

            var report = "### Provisioning Profile Summary (`\(resolvedURL.lastPathComponent)`):\n\n"
            report += "- **Profile Name**: `\(name)`\n"
            report += "- **Team**: `\(teamName)` (\(teamID))\n"
            report += "- **App ID Name**: `\(appIDName)`\n"
            if let exp = expiration {
                report += "- **Expiration Date**: `\(ISO8601DateFormatter().string(from: exp))`\n"
            }
            report += "\n#### Entitlements Included (\(entitlements.count)):\n"
            for (k, v) in entitlements {
                report += "- **\(k)**: `\(v)`\n"
            }

            return .success(report)
        } catch {
            return .failure("Failed to execute security cms -D: \(error.localizedDescription)")
        }
    }
}
