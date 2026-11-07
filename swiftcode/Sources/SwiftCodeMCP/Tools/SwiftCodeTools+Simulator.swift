import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
    var simulatorTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("device_list", "List Devices",
                 "Lists connected Apple devices via devicectl, falling back to xctrace. Fails clearly when no devices are found or the tooling is unavailable.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["devices": Schema.anyArray, "device_count": Schema.int, "source": Schema.str])) { h, call in
                try await h.listDevices(call)
            },
            tool("simulator_controller", "Simulator Controller",
                 "Controls Apple platform simulators (boot, shutdown, install app, open URL) via simctl.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'boot', 'shutdown', 'install', 'launch', or 'openurl'."),
                                       "device": Schema.string("Device name or UDID (e.g. 'booted', 'iPhone 16 Pro', or UUID)."),
                                       "appPath": Schema.string("Path to .app bundle when action is 'install'."),
                                       "bundleId": Schema.string("Bundle identifier when action is 'launch'."),
                                       "url": Schema.string("URL string when action is 'openurl'.")],
                                      required: ["action"]),
                 output: Schema.output(["action": Schema.str, "device": Schema.str, "output": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.simulatorController(call)
            },
        ]
    }

    func approveChangeWithoutFile(tool: String, summary: String, call: MCPToolCall) async throws {
        let root = (try? session(for: call)).map { Self.folder(of: $0.model).path }
            ?? FileManager.default.currentDirectoryPath
        let change = MCPChange(tool: tool, path: root, relativePath: ".", original: nil, proposed: "", summary: summary)
        guard await call.approve(change) else { throw MCPToolError(MCPServer.rejectedMessage) }
    }

    struct AppleSimulator: Sendable {
        var name: String
        var udid: String
        var state: String
        var runtime: String
        var isAvailable: Bool
    }

    nonisolated static func requireXcrun() throws {
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else {
            throw MCPToolError("xcrun not found at /usr/bin/xcrun. Install Xcode command line tools first.")
        }
    }

    nonisolated static func runXcrun(_ args: [String], timeout: TimeInterval = 60) async -> TerminalFixedRun? {
        (await Task.detached {
            Self.terminalRunFixed("/usr/bin/xcrun", args, environment: Self.terminalEnvironment(), timeout: timeout)
        }.value)
    }

    nonisolated static func appleSimulators() async -> [AppleSimulator] {
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else { return [] }
        guard let run = await runXcrun(["simctl", "list", "devices", "-j"], timeout: 60),
              run.exitCode == 0, !run.timedOut else { return [] }
        return parseSimctlDevices(run.stdout)
    }

    nonisolated static func parseSimctlDevices(_ stdout: String) -> [AppleSimulator] {
        guard let data = stdout.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = top["devices"] as? [String: Any] else { return [] }
        var out: [AppleSimulator] = []
        for runtime in devicesByRuntime.keys.sorted() {
            guard let devices = devicesByRuntime[runtime] as? [[String: Any]] else { continue }
            for device in devices.sorted(by: { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }) {
                out.append(AppleSimulator(name: device["name"] as? String ?? "(unknown)",
                                          udid: device["udid"] as? String ?? "(unknown)",
                                          state: device["state"] as? String ?? "(unknown)",
                                          runtime: runtime,
                                          isAvailable: device["isAvailable"] as? Bool ?? false))
            }
        }
        return out
    }

    func simctlBootOrShutdown(udid: String, action: String, call: MCPToolCall) async throws -> MCPToolResult {
        try Self.requireXcrun()
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "simctl \(action) Apple simulator \(udid)",
                                           call: call)
        guard let run = await Self.runXcrun(["simctl", action, udid], timeout: 120) else {
            throw MCPToolError("Failed to execute simctl: could not launch /usr/bin/xcrun")
        }
        let commandError = run.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let devices = await Self.appleSimulators()
        guard let found = devices.first(where: { $0.udid == udid }) else {
            if devices.isEmpty, run.exitCode != 0 {
                throw MCPToolError("Ran simctl \(action) (exit \(run.exitCode)) but verification failed: \(commandError.suffix(500))")
            }
            throw MCPToolError("Simulator with UDID \(udid) was not found in simctl list.")
        }
        let desired = action == "boot" ? "Booted" : "Shutdown"
        if found.state == desired {
            return .structured(["simulator": .string(udid), "state": .string(found.state)],
                               summary: "Simulator \(udid) is now \(found.state) (action: \(action)).")
        }
        let detail = commandError.isEmpty ? "simctl \(action) exited \(run.exitCode)" : commandError
        throw MCPToolError("Simulator \(udid) is \(found.state), expected \(desired). Detail: \(detail.suffix(1000))")
    }

    func listDevices(_ call: MCPToolCall) async throws -> MCPToolResult {
        try Self.requireXcrun()
        var devicectlError = ""
        if let run = await Self.runXcrun(["devicectl", "list", "devices", "-j"], timeout: 60) {
            devicectlError = "devicectl failed (exit \(run.exitCode)): \(run.stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500))"
            if run.exitCode == 0, let devices = Self.parseDevicectlJSON(run.stdout) {
                if devices.isEmpty {
                    throw MCPToolError("No connected devices found (devicectl returned an empty device list). Connect a device and trust this Mac, then try again.")
                }
                let lines = devices.map { d in
                    "\(d.name) (\(d.identifier))" + (d.platform.isEmpty ? "" : " - \(d.platform)")
                        + (d.pairing.isEmpty ? "" : " - \(d.pairing)")
                }
                let json: [AnyJSON] = devices.map { ["name": .string($0.name), "identifier": .string($0.identifier),
                                                     "platform": .string($0.platform), "pairing": .string($0.pairing)] }
                return .structured(["devices": .array(json), "device_count": .int(devices.count), "source": .string("devicectl")],
                                   summary: "Connected devices: \(devices.count)\n" + lines.joined(separator: "\n"))
            }
        }
        guard let trace = await Self.runXcrun(["xctrace", "list", "devices"], timeout: 60) else {
            throw MCPToolError("Device listing unavailable. devicectl failed to launch and the xctrace fallback could not launch either.")
        }
        if trace.exitCode == 0 {
            let lines = trace.stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("==") && !$0.hasPrefix("Devices") }
            if !lines.isEmpty {
                let json: [AnyJSON] = lines.map { ["name": .string($0), "identifier": .string(""), "platform": .string(""), "pairing": .string("")] }
                return .structured(["devices": .array(json), "device_count": .int(lines.count), "source": .string("xctrace")],
                                   summary: "Connected devices (via xctrace): \(lines.count)\n" + lines.joined(separator: "\n"))
            }
            throw MCPToolError("No connected devices found (xctrace returned an empty device list). Connect a device and trust this Mac, then try again.")
        }
        throw MCPToolError("Device listing unavailable. \(devicectlError.isEmpty ? "devicectl failed to launch" : devicectlError). xctrace fallback also failed (exit \(trace.exitCode)): \(trace.stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500)).")
    }

    nonisolated static func parseDevicectlJSON(_ text: String) -> [DevicectlDevice]? {
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
        return devices.map { device in
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
            return DevicectlDevice(name: name, identifier: identifier, platform: platform, pairing: pairing)
        }
    }

    func simulatorController(_ call: MCPToolCall) async throws -> MCPToolResult {
        let action = try call.require("action")
        let device = call.string("device") ?? "booted"
        var args: [String] = ["simctl"]
        switch action.lowercased() {
        case "boot":
            args.append(contentsOf: ["boot", device])
        case "shutdown":
            args.append(contentsOf: ["shutdown", device])
        case "install":
            guard let appPath = call.string("appPath"), !appPath.isEmpty else {
                throw MCPToolError("Action 'install' requires 'appPath'.")
            }
            let resolved: String
            if appPath.hasPrefix("/") {
                resolved = appPath
            } else if let s = try? session(for: call) {
                resolved = Self.folder(of: s.model).appendingPathComponent(appPath).path
            } else {
                resolved = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(appPath).path
            }
            args.append(contentsOf: ["install", device, resolved])
        case "launch":
            guard let bundleId = call.string("bundleId"), !bundleId.isEmpty else {
                throw MCPToolError("Action 'launch' requires 'bundleId'.")
            }
            args.append(contentsOf: ["launch", device, bundleId])
        case "openurl":
            guard let urlStr = call.string("url"), !urlStr.isEmpty else {
                throw MCPToolError("Action 'openurl' requires 'url'.")
            }
            args.append(contentsOf: ["openurl", device, urlStr])
        default:
            throw MCPToolError("Unsupported action '\(action)'. Supported: boot, shutdown, install, launch, openurl.")
        }
        try Self.requireXcrun()
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "simctl \(args.dropFirst().joined(separator: " "))",
                                           call: call)
        guard let run = await Self.runXcrun(args, timeout: 300) else {
            throw MCPToolError("Failed to execute simctl: could not launch /usr/bin/xcrun")
        }
        let out = (run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if run.exitCode == 0 {
            return .structured(["action": .string(action), "device": .string(device), "output": .string(out)],
                               summary: "Simulator operation '\(action)' succeeded on device '\(device)'. \(out)")
        }
        throw MCPToolError("Simulator command failed (exit code \(run.exitCode)): \(out)")
    }
}

struct DevicectlDevice: Sendable {
    var name: String
    var identifier: String
    var platform: String
    var pairing: String
}
