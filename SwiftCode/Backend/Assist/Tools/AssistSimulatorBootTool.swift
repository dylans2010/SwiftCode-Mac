import Foundation

public struct AssistSimulatorBootTool: AssistTool {
    public let id = "simulator_boot"
    public let name = "Boot Simulator"
    public let description = "Boots or shuts down a simulator by UDID via simctl, then verifies the resulting state."

    public init() {}

    public var capability: ToolCapability { .systemExecution }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Boots or shuts down a simulator by UDID.",
            properties: [
                "udid": JSONSchema(type: "string", description: "Simulator UDID in UUID format (required)."),
                "action": JSONSchema(type: "string", description: "boot or shutdown. Default is boot.")
            ],
            required: ["udid"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawUdid = input["udid"] as? String, !rawUdid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: udid")
        }
        let udid = rawUdid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: udid) != nil else {
            return .failure("Invalid udid: '\(udid)' is not a valid UUID.")
        }
        let rawAction = (input["action"] as? String ?? "boot").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard rawAction == "boot" || rawAction == "shutdown" else {
            return .failure("Invalid action: '\(rawAction)'. Expected boot or shutdown.")
        }
        let xcrunPath = "/usr/bin/xcrun"
        guard FileManager.default.fileExists(atPath: xcrunPath) else {
            return .failure("xcrun not found at /usr/bin/xcrun. Install Xcode command line tools first.")
        }
        let (exitCode, _, stderr) = runProcess(
            executablePath: xcrunPath,
            arguments: ["simctl", rawAction, udid],
            workingDirectory: context.workspaceRoot
        )
        let commandError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        // Verify via simctl list regardless of the boot/shutdown exit code,
        // because booting an already-booted device reports an error yet
        // leaves the device in the desired state.
        let (listExit, listStdout, listStderr) = runProcess(
            executablePath: xcrunPath,
            arguments: ["simctl", "list", "devices", "-j"],
            workingDirectory: context.workspaceRoot
        )
        guard listExit == 0,
              let data = listStdout.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = top["devices"] as? [String: Any] else {
            return .failure("Ran simctl \(rawAction) (exit \(exitCode)) but verification failed: \(listStderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500))")
        }
        var foundState: String?
        for (_, value) in devicesByRuntime {
            guard let devices = value as? [[String: Any]] else { continue }
            for device in devices {
                if (device["udid"] as? String) == udid {
                    foundState = device["state"] as? String
                    break
                }
            }
            if foundState != nil { break }
        }
        guard let state = foundState else {
            return .failure("Simulator with UDID \(udid) was not found in simctl list.")
        }
        let desired = rawAction == "boot" ? "Booted" : "Shutdown"
        if state == desired {
            return .success("Simulator \(udid) is now \(state) (action: \(rawAction)).", data: ["udid": udid, "action": rawAction, "state": state])
        } else {
            let detail = commandError.isEmpty ? "simctl \(rawAction) exited \(exitCode)" : commandError
            return .failure("Simulator \(udid) is \(state), expected \(desired). Detail: \(detail.suffix(1000))")
        }
    }

    private func runProcess(executablePath: String, arguments: [String], workingDirectory: URL?) -> (exitCode: Int32, stdout: String, stderr: String) {
        AssistToolingSupport.runProcess(executablePath: executablePath, arguments: arguments, workingDirectory: workingDirectory)
    }
}
