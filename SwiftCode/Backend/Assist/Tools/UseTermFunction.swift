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
                "explanation": JSONSchema(type: "string", description: "A concise explanation of why this terminal execution is required"),
                "estimatedImpact": JSONSchema(type: "string", description: "The estimated impact on the repository (e.g., 'no impact', 'creates new files')"),
                "modifiesRepo": JSONSchema(type: "string", description: "Whether the command modifies repository state ('true' or 'false')")
            ],
            required: ["command", "explanation", "estimatedImpact", "modifiesRepo"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let command = input["command"] as? String ?? ""
        let relativeWorkDir = input["workingDirectory"] as? String ?? ""
        let explanation = input["explanation"] as? String ?? ""
        let estimatedImpact = input["estimatedImpact"] as? String ?? ""
        let modifiesRepoStr = input["modifiesRepo"] as? String ?? "false"
        let modifiesRepo = (modifiesRepoStr.lowercased() == "true")

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

        // 3. Execute command asynchronously with live output streaming
        await context.logger.info("Executing approved command: \(command)", toolId: id)

        #if os(macOS)
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = workingDirURL

            // Set up environment to inherit standard paths (like homebrew, etc.)
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Store the process in AssistManager so it can be cancelled
            await MainActor.run {
                AssistManager.shared.activeProcess = process
                AssistManager.shared.terminalLiveOutput = ""
                AssistManager.shared.terminalRunning = true
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        AssistManager.shared.appendTerminalOutput(str)
                    }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        AssistManager.shared.appendTerminalOutput(str)
                    }
                }
            }

            try process.run()

            // Wait with a timeout (e.g. 5 minutes)
            let timeoutSeconds: Double = 300
            let task = Task {
                process.waitUntilExit()
            }

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }

            await task.value
            timeoutTask.cancel()

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let exitCode = Int(process.terminationStatus)
            let finalOutput = await AssistManager.shared.terminalLiveOutput

            await MainActor.run {
                AssistManager.shared.terminalRunning = false
                AssistManager.shared.terminalExitCode = exitCode
                AssistManager.shared.terminalCompleted = true
                AssistManager.shared.activeProcess = nil
            }

            let resultData: [String: String] = [
                "exit_code": "\(exitCode)",
                "output": finalOutput
            ]

            if exitCode == 0 {
                return .success("Terminal command executed successfully.\nExit code: 0\nOutput summary:\n\(finalOutput.suffix(2000))", data: resultData)
            } else {
                return .failure("Terminal command failed with exit code \(exitCode). Output:\n\(finalOutput.suffix(1000))", code: exitCode)
            }
        } catch {
            await MainActor.run {
                AssistManager.shared.terminalRunning = false
                AssistManager.shared.activeProcess = nil
            }
            return .failure("Process execution failed: \(error.localizedDescription)")
        }
        #else
        return .failure("Terminal execution is only supported on macOS")
        #endif
    }
}
