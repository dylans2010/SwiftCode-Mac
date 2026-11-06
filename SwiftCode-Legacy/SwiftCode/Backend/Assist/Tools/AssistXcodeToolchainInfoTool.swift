import Foundation

// Process policy: fixed-argv AssistArgvRunner (/usr/bin/xcodebuild, no shell).
// Listed in PROCESS_ALLOWLIST in Tools/validate_tools.py.

public struct AssistXcodeToolchainInfoTool: AssistTool {
    public let id = "xcode_toolchain_info"
    public let name = "Xcode Toolchain Info"
    public let description = "Reports the active Xcode version, build number, and installed SDKs via xcodebuild."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Reports Xcode toolchain info.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        func run(_ args: [String]) -> String {
            (try? AssistArgvRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: args,
                workingDirectory: context.workspaceRoot,
                timeout: 60
            ).output) ?? ""
        }
        let version = run(["-version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            return .failure("xcodebuild is not available (Xcode command-line tools missing?).")
        }
        let sdksRaw = run(["-showsdks"])
        var sdks: [String] = []
        for line in sdksRaw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("-sdk ") { sdks.append(t) }
        }
        var lines = ["Xcode toolchain:", version]
        lines.append("Installed SDKs (\(sdks.count)):")
        lines += sdks.prefix(20).map { "  \($0)" }
        return .success(lines.joined(separator: "\n"), data: ["sdkCount": "\(sdks.count)"])
    }
}
