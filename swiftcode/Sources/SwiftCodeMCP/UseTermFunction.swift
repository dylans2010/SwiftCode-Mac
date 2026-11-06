// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/UseTermFunction.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/UseTermFunction.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Allow-list / Full Access / Autopilot approval model: allow-listed commands run without a prompt and Full Access disables prompts
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AgentTerminalService — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AgentTerminalService.swift`)
//   - AssistManager — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistManager.swift`)
//   - TerminalApprovalSettings — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/TerminalApprovalSettings.swift`)
//   - ToolCapability — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - ToolRiskLevel — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Terminal.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

import Foundation
import SwiftCodeAssistant

// NOTE (MCP-DEP, 2026-11-06): TerminalApprovalRequest moved to SwiftCodeAssistant
// (swiftcode/Sources/SwiftCodeAssistant/TerminalApprovalRequest.swift) — it is a
// Foundation-only struct, and SwiftCodeAssistant (which cannot import SwiftCodeMCP)
// needs it. This file uses it through `import SwiftCodeAssistant` below.
public struct UseTermFunction: AssistTool {
    public let id = "use_terminal"
    public let name = "Use Terminal"
    public let description = "Executes terminal commands on the user's machine. Commands on the user's allow-list (Assist Settings > Terminal Command Approvals), or any command when Full Access is enabled, run without an approval prompt; all other commands require explicit user approval."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Executes terminal commands on the user's machine with explicit user approval.",
            properties: [
                "command": JSONSchema(type: "string", description: "The full shell command to run (e.g., 'git status' or 'swift test')"),
                "workingDirectory": JSONSchema(type: "string", description: "The relative path from project root where command should run (optional)"),
                "explanation": JSONSchema(type: "string", description: "A concise explanation of why this terminal execution is required (optional)"),
                "estimatedImpact": JSONSchema(type: "string", description: "The estimated impact on the repository (optional)"),
                "modifiesRepo": JSONSchema(type: "string", description: "Whether the command modifies repository state ('true' or 'false', optional)")
            ],
            required: ["command"]
        )
    }

    public var capability: ToolCapability { .systemExecution }
    public var riskLevel: ToolRiskLevel { .execution }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let command = (input["command"] as? String) ?? (input["cmd"] as? String) ?? ""
        let relativeWorkDir = (input["workingDirectory"] as? String) ?? (input["cwd"] as? String) ?? ""
        let explanation = (input["explanation"] as? String) ?? "Executing shell command"
        let estimatedImpact = (input["estimatedImpact"] as? String) ?? "Runs terminal command"
        let modifiesRepo: Bool
        if let boolVal = input["modifiesRepo"] as? Bool {
            modifiesRepo = boolVal
        } else if let strVal = input["modifiesRepo"] as? String {
            modifiesRepo = (strVal.lowercased() == "true")
        } else {
            modifiesRepo = false
        }

        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Command cannot be empty", code: .missingArgument)
        }

        // 1. Resolve working directory URL through the filesystem layer so
        // traversal / symlink / containment checks apply. Empty means the
        // session working directory (see dir_cd), not the workspace root.
        let workingDirURL: URL
        if relativeWorkDir.isEmpty {
            workingDirURL = context.fileSystem.currentDirectory
        } else {
            do {
                workingDirURL = try context.fileSystem.resolve(relativeWorkDir)
            } catch {
                return .failure("Invalid workingDirectory '\(relativeWorkDir)': \(error.localizedDescription)", code: .invalidInput)
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: workingDirURL.path, isDirectory: &isDir), isDir.boolValue else {
                return .failure("workingDirectory does not exist or is not a directory: \(relativeWorkDir)", code: .notFound)
            }
        }

        // Ensure isolated scripts directory exists if targeted
        if workingDirURL.path.hasPrefix("/tmp/swiftcode/scripts") {
            try? FileManager.default.createDirectory(atPath: "/tmp/swiftcode/scripts", withIntermediateDirectories: true)
        }

        // 2. Approval policy: If Assist is on Autopilot, BYPASS the permissions COMPLETELY at a system level.
        // Otherwise, the user's allow-list and Full Access toggle decide whether this
        // command may run without an explicit approval prompt.
        let isAutopilot = context.sessionExecutionMode == .autopilot ||
            (UserDefaults.standard.string(forKey: "com.swiftcode.assist.executionMode") ?? "").lowercased() == ExecutionMode.autopilot.rawValue
        let bypassesApproval = isAutopilot || TerminalApprovalSettings.shared.isApprovalBypassed(for: command)

        let approved: Bool
        if bypassesApproval {
            let reason = isAutopilot ? "Autopilot mode" : "allow-list / Full Access"
            await context.logger.info("Terminal command bypasses approval (\(reason)): \(command)", toolId: id)
            approved = true
        } else {
            // 2a. Request user approval through AssistManager
            let request = TerminalApprovalRequest(
                id: UUID(),
                command: command,
                workingDirectory: relativeWorkDir.isEmpty ? "." : relativeWorkDir,
                explanation: explanation,
                estimatedImpact: estimatedImpact,
                modifiesRepo: modifiesRepo
            )

            await context.logger.info("Requesting terminal approval: \(command)", toolId: id)

            approved = await AssistManager.shared.requestTerminalApproval(request)
        }
        if !approved {
            await context.logger.warning("Terminal command rejected by user: \(command)", toolId: id)
            return .failure("Terminal execution rejected by user.", code: .cancelled)
        }

        // 3. Execute command asynchronously with live output streaming via AgentTerminalService
        await context.logger.info("Executing approved command: \(command)", toolId: id)

        do {
            let res = try await AgentTerminalService.shared.execute(
                command: command,
                workingDirectory: workingDirURL
            )

            let diagStrings = res.diagnostics.map { "\($0.filePath):\($0.line): \($0.severity.rawValue): \($0.message)" }
            // Truncation is marked explicitly: a long build log must never
            // look complete when it was cut off.
            let stdoutTruncated = res.stdout.count > 3000
            let stderrTruncated = res.stderr.count > 2000
            let stdoutTail = String(res.stdout.suffix(3000)) + (stdoutTruncated ? "\n… [stdout truncated to last 3000 chars]" : "")
            let stderrTail = String(res.stderr.suffix(2000)) + (stderrTruncated ? "\n… [stderr truncated to last 2000 chars]" : "")
            let resultData: [String: String] = [
                "command": res.command,
                "workingDirectory": res.workingDirectory,
                "stdout": stdoutTail,
                "stderr": stderrTail,
                "stdoutTruncated": stdoutTruncated ? "true" : "false",
                "stderrTruncated": stderrTruncated ? "true" : "false",
                "exitCode": "\(res.exitCode)",
                "duration": String(format: "%.2fs", res.duration)
            ]

            if res.isSuccess {
                let stdoutShown = res.stdout.isEmpty ? "(No stdout output)" : String(res.stdout.suffix(2000)) + (res.stdout.count > 2000 ? "\n… [stdout truncated to last 2000 chars]" : "")
                return AssistToolResult(
                    success: true,
                    output: "Terminal command executed successfully (exit code 0 in \(String(format: "%.2fs", res.duration))):\n\(stdoutShown)",
                    data: resultData,
                    diagnostics: diagStrings,
                    duration: res.duration,
                    exitCode: 0,
                    suggestedNextActions: ["project_diff", "project_build"]
                )
            } else {
                let errSummary = res.stderr.isEmpty ? res.stdout : res.stderr
                return AssistToolResult(
                    success: false,
                    output: "Terminal command failed with exit code \(res.exitCode) (\(String(format: "%.2fs", res.duration))):\n\(errSummary.suffix(1500))",
                    data: resultData,
                    error: "Command exited with non-zero status \(res.exitCode)",
                    errorCode: res.exitCode,
                    diagnostics: diagStrings,
                    duration: res.duration,
                    exitCode: Int32(res.exitCode),
                    suggestedNextActions: ["file_read", "project_diff"]
                )
            }
        } catch {
            return .failure("Process execution failed: \(error.localizedDescription)", code: .executionFailed)
        }
    }
}
