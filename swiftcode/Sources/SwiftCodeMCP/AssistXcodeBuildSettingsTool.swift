// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/AssistXcodeBuildSettingsTool.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/AssistXcodeBuildSettingsTool.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Live xcodebuild -showBuildSettings execution with fully resolved settings (SDK paths, resolved values); destination reports only 11 key settings statically merged from the .pbxproj
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - ToolCapability — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - ToolRiskLevel — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+ProjectModel.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

//
//  AssistXcodeBuildSettingsTool.swift
//  SwiftCode
//

import Foundation

public struct AssistXcodeBuildSettingsTool: AssistTool {
    public let id = "xcode_build_settings_inspector"
    public let name = "Xcode Build Settings Inspector"
    public let description = "Inspects and extracts active build configuration settings, flags, and paths via xcodebuild."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Queries build settings for the active Xcode project or target (e.g. SWIFT_VERSION, PRODUCT_BUNDLE_IDENTIFIER, ARCHS).",
            properties: [
                "target": JSONSchema(type: "string", description: "Optional target name to query build settings for."),
                "settingKey": JSONSchema(type: "string", description: "Optional specific build setting key to extract (e.g. PRODUCT_BUNDLE_IDENTIFIER, SWIFT_VERSION).")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let target = input["target"] as? String
        let specificKey = input["settingKey"] as? String

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        var args = ["xcodebuild", "-showBuildSettings"]
        if let tgt = target, !tgt.isEmpty {
            args.append(contentsOf: ["-target", tgt])
        }
        proc.arguments = args
        proc.currentDirectoryURL = context.workspaceRoot

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)

            var settingsMap: [String: String] = [:]
            for line in output.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: " = ")
                if parts.count == 2 {
                    let k = parts[0].trimmingCharacters(in: .whitespaces)
                    let v = parts[1].trimmingCharacters(in: .whitespaces)
                    settingsMap[k] = v
                }
            }

            if let key = specificKey, !key.isEmpty {
                if let val = settingsMap[key] {
                    return .success("\(key) = \(val)")
                } else {
                    return .failure("Build setting '\(key)' was not found in xcodebuild output.")
                }
            }

            // Summary of primary settings
            let keySettings = [
                "TARGET_NAME",
                "PRODUCT_NAME",
                "PRODUCT_BUNDLE_IDENTIFIER",
                "SWIFT_VERSION",
                "IPHONEOS_DEPLOYMENT_TARGET",
                "MACOSX_DEPLOYMENT_TARGET",
                "SDK_NAME",
                "ARCHS",
                "CONFIGURATION",
                "INFOPLIST_FILE",
                "ENABLE_PREVIEWS"
            ]

            var summary = "### Active Xcode Build Settings:\n\n"
            for k in keySettings {
                if let v = settingsMap[k] {
                    summary += "- **\(k)**: `\(v)`\n"
                }
            }
            if settingsMap.isEmpty {
                return .success("No Xcode build settings returned. Ensure an .xcodeproj exists in the workspace.")
            }
            return .success(summary)
        } catch {
            return .failure("Failed to execute xcodebuild -showBuildSettings: \(error.localizedDescription)")
        }
    }
}
