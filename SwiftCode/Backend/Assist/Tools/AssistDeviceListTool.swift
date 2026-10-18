import Foundation

public struct AssistDeviceListTool: AssistTool {
    public let id = "device_list"
    public let name = "List Devices"
    public let description = "Lists connected Apple devices via devicectl, falling back to xctrace. Fails clearly when no devices are found or the tooling is unavailable."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists connected devices. No parameters.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let xcrunPath = "/usr/bin/xcrun"
        guard FileManager.default.fileExists(atPath: xcrunPath) else {
            return .failure("xcrun not found at /usr/bin/xcrun. Install Xcode command line tools first.")
        }
        let (devicectlExit, devicectlStdout, devicectlStderr) = runProcess(
            executablePath: xcrunPath,
            arguments: ["devicectl", "list", "devices", "-j"],
            workingDirectory: context.workspaceRoot
        )
        if devicectlExit == 0, let devices = parseDevicectlJSON(devicectlStdout), !devices.isEmpty {
            let output = "Connected devices: \(devices.count)\n" + devices.joined(separator: "\n")
            return .success(output, data: ["device_count": "\(devices.count)", "source": "devicectl"])
        }
        if devicectlExit == 0, let devices = parseDevicectlJSON(devicectlStdout), devices.isEmpty {
            return .failure("No connected devices found (devicectl returned an empty device list). Connect a device and trust this Mac, then try again.")
        }

        // Fallback: xctrace text listing.
        let (xctraceExit, xctraceStdout, xctraceStderr) = runProcess(
            executablePath: xcrunPath,
            arguments: ["xctrace", "list", "devices"],
            workingDirectory: context.workspaceRoot
        )
        if xctraceExit == 0 {
            let lines = xctraceStdout
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("==") && !$0.hasPrefix("Devices") }
            if !lines.isEmpty {
                let output = "Connected devices (via xctrace): \(lines.count)\n" + lines.joined(separator: "\n")
                return .success(output, data: ["device_count": "\(lines.count)", "source": "xctrace"])
            }
            return .failure("No connected devices found (xctrace returned an empty device list). Connect a device and trust this Mac, then try again.")
        }
        return .failure("Device listing unavailable. devicectl failed (exit \(devicectlExit)): \(devicectlStderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500)). xctrace fallback also failed (exit \(xctraceExit)): \(xctraceStderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500)).")
    }

    private func parseDevicectlJSON(_ text: String) -> [String]? {
        guard let data = text.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var rawDevices: [[String: Any]]?
        if let result = top["result"] as? [String: Any], let devices = result["devices"] as? [[String: Any]] {
            rawDevices = devices
        } else if let devices = top["devices"] as? [[String: Any]] {
            rawDevices = devices
        }
        guard let devices = rawDevices else { return nil }
        var lines: [String] = []
        for device in devices {
            let identifier = device["identifier"] as? String ?? device["udid"] as? String ?? "(unknown)"
            var name = "(unknown)"
            var platform = ""
            var pairing = ""
            if let props = device["deviceProperties"] as? [String: Any] {
                name = props["name"] as? String ?? name
            }
            if let hardware = device["hardwareProperties"] as? [String: Any] {
                platform = hardware["platform"] as? String ?? ""
            }
            if let connection = device["connectionProperties"] as? [String: Any] {
                pairing = connection["pairingState"] as? String ?? ""
            }
            var line = "\(name) (\(identifier))"
            if !platform.isEmpty { line += " - \(platform)" }
            if !pairing.isEmpty { line += " - \(pairing)" }
            lines.append(line)
        }
        return lines
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
