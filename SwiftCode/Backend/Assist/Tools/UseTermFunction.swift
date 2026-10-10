import Foundation

public struct TerminalApprovalRequest: Identifiable, Sendable {
    public let id: UUID
    public let command: String
    public let workingDirectory: String
    public let explanation: String
    public let estimatedImpact: String
    public let modifiesRepo: Bool

    public init(id: UUID = UUID(), command: String, workingDirectory: String, explanation: String, estimatedImpact: String, modifiesRepo: Bool) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.explanation = explanation
        self.estimatedImpact = estimatedImpact
        self.modifiesRepo = modifiesRepo
    }
}

public struct UseTermFunction: AssistTool {
    public let id = "use_terminal"
    public let name = "Use Terminal"
    public let description = "Executes arbitrary terminal commands on the user's machine after explicit user approval."

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
            return .failure("Command cannot be empty")
        }

        // 1. Resolve working directory URL
        let workingDirURL: URL
        if !relativeWorkDir.isEmpty {
            workingDirURL = context.workspaceRoot.appendingPathComponent(relativeWorkDir)
        } else {
            workingDirURL = context.workspaceRoot
        }

        // 2. Request user approval through AssistManager
        let request = TerminalApprovalRequest(
            id: UUID(),
            command: command,
            workingDirectory: relativeWorkDir.isEmpty ? "." : relativeWorkDir,
            explanation: explanation,
            estimatedImpact: estimatedImpact,
            modifiesRepo: modifiesRepo
        )

        await context.logger.info("Requesting terminal approval: \(command)", toolId: id)

        let approved = await AssistManager.shared.requestTerminalApproval(request)
        if !approved {
            await context.logger.warning("Terminal command rejected by user: \(command)", toolId: id)
            return .failure("Terminal execution rejected by user.")
        }

        // 3. Execute command asynchronously with live output streaming via AgentTerminalService
        await context.logger.info("Executing approved command: \(command)", toolId: id)

        do {
            let res = try await AgentTerminalService.shared.execute(
                command: command,
                workingDirectory: workingDirURL
            )

            let diagStrings = res.diagnostics.map { "\($0.filePath):\($0.line): \($0.severity.rawValue): \($0.message)" }
            let resultData: [String: String] = [
                "command": res.command,
                "workingDirectory": res.workingDirectory,
                "stdout": String(res.stdout.suffix(3000)),
                "stderr": String(res.stderr.suffix(2000)),
                "exitCode": "\(res.exitCode)",
                "duration": String(format: "%.2fs", res.duration)
            ]

            if res.isSuccess {
                return AssistToolResult(
                    success: true,
                    output: "Terminal command executed successfully (exit code 0 in \(String(format: "%.2fs", res.duration))):\n\(res.stdout.isEmpty ? "(No stdout output)" : res.stdout.suffix(2000))",
                    data: resultData,
                    diagnostics: diagStrings,
                    duration: res.duration,
                    exitCode: 0,
                    suggestedNextActions: ["project_status", "project_build"]
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
                    suggestedNextActions: ["file_read", "replan"]
                )
            }
        } catch {
            return .failure("Process execution failed: \(error.localizedDescription)")
        }
    }
}
