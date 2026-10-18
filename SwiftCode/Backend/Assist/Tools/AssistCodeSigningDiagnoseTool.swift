import Foundation

// Process policy: fixed-argv AssistArgvRunner (/usr/bin/codesign, no shell).
// Listed in PROCESS_ALLOWLIST in Tools/validate_tools.py.

public struct AssistCodeSigningDiagnoseTool: AssistTool {
    public let id = "code_signing_diagnose"
    public let name = "Code Signing Diagnose"
    public let description = "Diagnoses code-signing state of a built .app/.framework: signature validity, authority chain, team identifier, and hardened-runtime flags."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Diagnoses code signing of a built product.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the .app, .framework, or binary.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot),
              FileManager.default.fileExists(atPath: url.path) else {
            return .failure("No file at path: \(raw)")
        }
        let run: AssistArgvRunner.Result
        do {
            run = try AssistArgvRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["-dv", "--verbose=4", url.path],
                workingDirectory: context.workspaceRoot,
                timeout: 60
            )
        } catch {
            return .failure("Failed to run codesign: \(error.localizedDescription)")
        }
        if run.timedOut {
            return .failure("codesign timed out after 60s on \(raw).")
        }
        let output = run.output
        var info: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { info[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1] }
        }
        var findings: [String] = []
        if output.contains("code object is not signed") {
            findings.append("NOT SIGNED: the product has no code signature.")
        } else if run.exitCode == 0 {
            findings.append("Signature present and verifiable by codesign.")
        }
        if output.contains("adhoc") || info["Signature"] == "adhoc" {
            findings.append("Ad-hoc signature: distribution and notarization will fail; use a Developer ID or App Store identity.")
        }
        if let team = info["TeamIdentifier"], team != "not set" {
            findings.append("Team identifier: \(team)")
        } else {
            findings.append("No team identifier embedded.")
        }
        if output.contains("flags=0x10000") || output.contains("runtime") {
            findings.append("Hardened runtime flag detected.")
        }
        var lines = ["Code signing diagnosis for \(raw) (exit \(run.exitCode)):"]
        lines += findings.map { "- \($0)" }
        if let authority = info["Authority"] { lines.append("- Authority: \(authority)") }
        if let identifier = info["Identifier"] { lines.append("- Identifier: \(identifier)") }
        if let format = info["Format"] { lines.append("- Format: \(format)") }
        return .success(lines.joined(separator: "\n"), data: [
            "exitCode": "\(run.exitCode)",
            "teamIdentifier": info["TeamIdentifier"] ?? "",
            "authority": info["Authority"] ?? "",
            "signed": output.contains("code object is not signed") ? "false" : "true"
        ])
    }
}
