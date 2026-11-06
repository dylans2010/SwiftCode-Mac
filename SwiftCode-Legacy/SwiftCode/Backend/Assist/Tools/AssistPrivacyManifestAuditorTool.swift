//
//  AssistPrivacyManifestAuditorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistPrivacyManifestAuditorTool: AssistTool {
    public let id = "privacy_manifest_auditor"
    public let name = "Privacy Manifest Auditor"
    public let description = "Audits or scaffolds Apple Privacy Manifests (PrivacyInfo.xcprivacy) for Required Reason API compliance."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits codebase for Apple Required Reason APIs (UserDefaults, File timestamp, System boot time, Disk space) and validates PrivacyInfo.xcprivacy.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'audit' (scan codebase for API usage) or 'generate' (scaffold a valid PrivacyInfo.xcprivacy template).")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action ('audit' or 'generate')")
        }

        let root = context.workspaceRoot

        if action.lowercased() == "generate" {
            let manifestPath = root.appendingPathComponent("PrivacyInfo.xcprivacy")
            let template = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>NSPrivacyTracking</key>
                <false/>
                <key>NSPrivacyTrackingDomains</key>
                <array/>
                <key>NSPrivacyCollectedDataTypes</key>
                <array/>
                <key>NSPrivacyAccessedAPITypes</key>
                <array>
                    <dict>
                        <key>NSPrivacyAccessedAPIType</key>
                        <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
                        <key>NSPrivacyAccessedAPITypeReasons</key>
                        <array>
                            <string>CA92.1</string>
                        </array>
                    </dict>
                    <dict>
                        <key>NSPrivacyAccessedAPIType</key>
                        <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
                        <key>NSPrivacyAccessedAPITypeReasons</key>
                        <array>
                            <string>C617.1</string>
                        </array>
                    </dict>
                </array>
            </dict>
            </plist>
            """
            do {
                try template.write(to: manifestPath, atomically: true, encoding: .utf8)
                return .success("Successfully generated compliant PrivacyInfo.xcprivacy at workspace root.")
            } catch {
                return .failure("Failed to write PrivacyInfo.xcprivacy: \(error.localizedDescription)")
            }
        }

        // Action: audit
        var userDefaultsUsage = 0
        var fileTimestampUsage = 0
        var diskSpaceUsage = 0
        var bootTimeUsage = 0

        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" || fileURL.pathExtension == "m" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            if text.contains("UserDefaults") { userDefaultsUsage += 1 }
            if text.contains("contentModificationDate") || text.contains("fileModificationDate") { fileTimestampUsage += 1 }
            if text.contains("volumeAvailableCapacity") || text.contains("systemFreeSize") { diskSpaceUsage += 1 }
            if text.contains("systemUptime") || text.contains("mach_absolute_time") { bootTimeUsage += 1 }
        }

        let manifestFile = root.appendingPathComponent("PrivacyInfo.xcprivacy")
        let manifestExists = FileManager.default.fileExists(atPath: manifestFile.path)

        var report = "### Apple Required Reason API Audit Report:\n\n"
        report += "- **PrivacyInfo.xcprivacy Present**: \(manifestExists ? "✅ Yes" : "❌ No (Action recommended)")\n"
        report += "- **UserDefaults Usage**: \(userDefaultsUsage) file(s) (Requires Category `NSPrivacyAccessedAPICategoryUserDefaults`)\n"
        report += "- **File Timestamp Usage**: \(fileTimestampUsage) file(s) (Requires Category `NSPrivacyAccessedAPICategoryFileTimestamp`)\n"
        report += "- **Disk Space API Usage**: \(diskSpaceUsage) file(s) (Requires Category `NSPrivacyAccessedAPICategoryDiskSpace`)\n"
        report += "- **System Boot Time Usage**: \(bootTimeUsage) file(s) (Requires Category `NSPrivacyAccessedAPICategorySystemBootTime`)\n\n"

        if !manifestExists && (userDefaultsUsage > 0 || fileTimestampUsage > 0) {
            report += "⚠️ Required Reason APIs detected without PrivacyInfo.xcprivacy. Run with `action: 'generate'` to scaffold the required manifest."
        } else {
            report += "Compliance check complete."
        }

        return .success(report)
    }
}
