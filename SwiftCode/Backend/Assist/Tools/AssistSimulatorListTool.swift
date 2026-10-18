import Foundation

public struct AssistSimulatorListTool: AssistTool {
    public let id = "simulator_list"
    public let name = "List Simulators"
    public let description = "Lists available iOS/tvOS/watchOS simulators with runtime, state, and UDID via simctl."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists available simulators. No parameters.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let xcrunPath = "/usr/bin/xcrun"
        guard FileManager.default.fileExists(atPath: xcrunPath) else {
            return .failure("xcrun not found at /usr/bin/xcrun. Install Xcode command line tools first.")
        }
        let (exitCode, stdout, stderr) = runProcess(
            executablePath: xcrunPath,
            arguments: ["simctl", "list", "devices", "-j"],
            workingDirectory: context.workspaceRoot
        )
        guard exitCode == 0 else {
            return .failure("simctl list failed (exit \(exitCode)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(1000))")
        }
        guard let data = stdout.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = top["devices"] as? [String: Any] else {
            return .failure("Could not parse simctl JSON output.")
        }

        var lines: [String] = []
        var total = 0
        var available = 0
        var booted = 0
        for runtime in devicesByRuntime.keys.sorted() {
            guard let devices = devicesByRuntime[runtime] as? [[String: Any]] else { continue }
            lines.append("Runtime: \(runtime)")
            for device in devices.sorted(by: { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }) {
                let name = device["name"] as? String ?? "(unknown)"
                let udid = device["udid"] as? String ?? "(unknown)"
                let state = device["state"] as? String ?? "(unknown)"
                let isAvailable = device["isAvailable"] as? Bool ?? false
                total += 1
                if isAvailable { available += 1 }
                if state == "Booted" { booted += 1 }
                lines.append("  \(name) (\(udid)) - \(state) - available: \(isAvailable ? "yes" : "no")")
            }
        }
        if total == 0 {
            return .failure("No simulators found. No runtimes or devices are installed.")
        }
        let output = "Simulators: \(total) device(s) across \(devicesByRuntime.keys.count) runtime(s), \(available) available, \(booted) booted.\n" + lines.joined(separator: "\n")
        return .success(output, data: [
            "device_count": "\(total)",
            "runtime_count": "\(devicesByRuntime.keys.count)",
            "available_count": "\(available)",
            "booted_count": "\(booted)"
        ])
    }

    private func runProcess(executablePath: String, arguments: [String], workingDirectory: URL?) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        var outText = ""
        var errText = ""
        let lock = NSLock()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) {
                lock.lock(); outText += text; lock.unlock()
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) {
                lock.lock(); errText += text; lock.unlock()
            }
        }
        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return (-1, "", "Failed to launch \(executablePath): \(error.localizedDescription)")
        }
        process.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        let outRemainder = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errRemainder = errPipe.fileHandleForReading.readDataToEndOfFile()
        if let remainder = String(data: outRemainder, encoding: .utf8), !remainder.isEmpty {
            outText += remainder
        }
        if let remainder = String(data: errRemainder, encoding: .utf8), !remainder.isEmpty {
            errText += remainder
        }
        return (process.terminationStatus, outText, errText)
    }
}
