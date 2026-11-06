import Foundation
import YcodeAssistant
import YcodeIDECore

/// The ported Legacy Simulator / device tools (Wave 5).
///
/// Behaviour source: Legacy's `AssistDeviceListTool`,
/// `AssistSimulatorBootTool`, `AssistSimulatorControllerTool` and
/// `AssistSimulatorListTool` (Dylan's own code, ported under MIT).
/// The 4 IDs below were verified live from the Legacy registry
/// (`registerAllTools` + each tool's `id`).
///
/// Conventions, following Waves 1–4:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter Wave 1 adds to every tool. Descriptions
///   are Legacy's verbatim. Structured data keeps Legacy's keys,
///   with typed JSON values (integers and booleans) the way Ycode's
///   other tools do — Legacy's string-only map is not reproduced.
/// * Risk → annotations follows the catalogue §1.3 table, extended
///   the way Wave 3 extended it for `.execution` (`readOnly:
///   false, idempotent: false`, `writes: true`):
///   `safeRead` → read-only/idempotent, `writes: false`;
///   `safeMutation` → `readOnly: false, idempotent: true`,
///   `writes: true`; `.execution` → `readOnly: false,
///   idempotent: false`, `writes: true`.
/// * Every local command runs as a subprocess argument vector —
///   never a shell — via Wave 4's `terminalRunFixed` (off the main
///   actor), with stdin closed. All four tools drive Apple's
///   `xcrun`/`simctl`/`devicectl`/`xctrace` on macOS; where `xcrun`
///   is absent they fail with Legacy's exact message instead of
///   pretending the Ycode Simulator is a substitute.
///
/// ID COLLISION — read before wiring (Wave 5 coordinator follow-up):
///
/// * Ycode ALREADY registers `simulator_boot` and `simulator_list`
///   in `YcodeTools+Run.swift` (`runTools`), driving the Ycode
///   Simulator on its remote Linux host. Legacy's tools with the
///   same IDs target Apple Simulator via `simctl` — same IDs,
///   different backend. They are NOT re-registered here (duplicate
///   IDs would break the catalogue's uniqueness invariant and
///   `MCPServerTests`); instead the existing registrations are
///   ALIGNED in place in `YcodeTools+Run.swift`, following the
///   Wave 1 `file_read` / Wave 2 `file_write` precedent:
///   - `simulator_list` keeps its Ycode output (`simulators`,
///     `configured`) and gains an `appleSimulators` array with
///     Legacy's `simctl list devices -j` listing (empty when
///     `xcrun` is absent). Legacy's counts become the array's
///     length; the runtime grouping is preserved in each entry's
///     `runtime`.
///   - `simulator_boot` keeps its Ycode behaviour (a `simulator`
///     name/id, default the first) and gains Legacy's parameters
///     `udid` (required for the Apple path) and `action`
///     (`boot`/`shutdown`, default `boot`). With a `udid` it runs
///     Legacy's `simctl` boot/shutdown with Legacy's verification
///     pass (re-list and compare the state); without one it boots
///     the Ycode Simulator as before.
///   What was aligned vs what differs is recorded per tool in
///   `specs/ide/assist-artboards-media-tools.md` (Part A §3).
/// * No new `Package.swift` dependency is needed for any of this:
///   the tools call `xcrun` as a subprocess (Wave 4's runner),
///   they do not import `YcodeSimFeatures` — that target is the
///   Ycode Simulator's guest-feature channels (health, audio,
///   location), not an Apple `simctl` wrapper, and nothing in it
///   is used here. `YcodeMCP` must NOT gain a `YcodeSimFeatures`
///   dependency for this wave.
///
/// Implemented here (2 new registrations): `device_list`,
/// `simulator_controller`. Aligned in `YcodeTools+Run.swift` (2):
/// `simulator_boot`, `simulator_list`.
///
/// Relationship notes (overlapping behaviour, not duplication):
///
/// * `simulator_controller`'s `boot`/`shutdown` actions overlap
///   the aligned `simulator_boot` (which takes a UDID for the
///   Apple path, or a Ycode device name for the remote path) and
///   Ycode's `simulator_shutdown` (Ycode remote only). The
///   controller is the `simctl`-native multi-action entry point
///   (boot, shutdown, install, launch, openurl) on any device
///   selector `simctl` accepts (`booted`, a name, or a UDID);
///   `openurl` and `install` have no Ycode equivalent.
/// * `device_list` (physical devices via `devicectl`, falling back
///   to `xctrace`) has no Ycode equivalent: the Device Hub lists
///   physical devices in the UI, but no MCP tool does.
/// * `simulator_controller`'s `launch` overlaps Ycode's
///   `simulator_launch_app` only in outcome (an app launched on a
///   simulator): the Ycode tool installs + launches on the remote
///   Ycode Simulator, this one launches an already-installed
///   bundle id on an Apple simulator.
///
/// Wiring (coordinator): add `simulatorTools` to `installTools()` in
/// `YcodeTools.swift` (`server.tools = … + artboardTools +
/// simulatorTools`). Do NOT add `simulator_boot` or `simulator_list`
/// here — they already live in `runTools`.
extension YcodeMCPHost {
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

    // MARK: - Approval for non-file mutations

    /// Asks the approval path about one non-file operation before
    /// it runs (the Wave 2 §6.2 / Wave 4 `terminalApproveChange`
    /// shape, without requiring an open workspace): the change's
    /// path is the workspace root when one is open, else the
    /// current directory, since the operation has no single file.
    /// In read-only mode the server refuses `writes: true` tools
    /// before the handler runs, so this is only reached when the
    /// policy allows the write.
    func approveChangeWithoutFile(tool: String, summary: String, call: MCPToolCall) async throws {
        let root = (try? session(for: call)).map { Self.folder(of: $0.model).path }
            ?? FileManager.default.currentDirectoryPath
        let change = MCPChange(tool: tool, path: root, relativePath: ".", original: nil, proposed: "", summary: summary)
        guard await call.approve(change) else { throw MCPToolError(MCPServer.rejectedMessage) }
    }

    // MARK: - Apple simulators via simctl (shared by the aligned tools)

    /// One Apple simulator, as `simctl list devices -j` reports it.
    struct AppleSimulator: Sendable {
        var name: String
        var udid: String
        var state: String
        var runtime: String
        var isAvailable: Bool
    }

    /// Legacy's `xcrun` precondition, with Legacy's message.
    nonisolated static func requireXcrun() throws {
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else {
            throw MCPToolError("xcrun not found at /usr/bin/xcrun. Install Xcode command line tools first.")
        }
    }

    /// Runs `xcrun` with a fixed argument vector (never a shell),
    /// off the main actor because it blocks. `nil` when the process
    /// cannot start at all.
    nonisolated static func runXcrun(_ args: [String], timeout: TimeInterval = 60) async -> TerminalFixedRun? {
        await Task.detached {
            Self.terminalRunFixed("/usr/bin/xcrun", args, environment: Self.terminalEnvironment(), timeout: timeout)
        }.value
    }

    /// Legacy's `simctl list devices -j`, parsed the way Legacy's
    /// `AssistSimulatorListTool` parses it. Empty when `xcrun` is
    /// absent or the listing fails — the aligned `simulator_list`
    /// reports that as an empty Apple section, while the dedicated
    /// tools fail loudly instead.
    nonisolated static func appleSimulators() async -> [AppleSimulator] {
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else { return [] }
        guard let run = await runXcrun(["simctl", "list", "devices", "-j"], timeout: 60),
              run.exitCode == 0, !run.timedOut else { return [] }
        return parseSimctlDevices(run.stdout)
    }

    /// Parses `simctl list devices -j` output: `devices` maps a
    /// runtime identifier to its devices. Sorted by runtime, then
    /// by device name — Legacy's order.
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

    /// Legacy's `AssistSimulatorBootTool` Apple path: `simctl
    /// <action> <udid>`, then verify by re-listing regardless of
    /// the first command's exit code (booting an already-booted
    /// device reports an error yet leaves it in the desired state).
    /// `call` is the real tool call, so the approval gate uses the
    /// server's policy (a synthetic call would default-approve).
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

    // MARK: - `device_list`

    func listDevices(_ call: MCPToolCall) async throws -> MCPToolResult {
        try Self.requireXcrun()
        // devicectl first (JSON), xctrace text listing as fallback —
        // Legacy's order and messages.
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

    /// Legacy's `parseDevicectlJSON`: `result.devices` or a top-level
    /// `devices` array, each with `identifier`/`udid`,
    /// `deviceProperties.name`, `hardwareProperties.platform` and
    /// `connectionProperties.pairingState`.
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

    // MARK: - `simulator_controller`

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

/// One device from `devicectl list devices -j`.
struct DevicectlDevice: Sendable {
    var name: String
    var identifier: String
    var platform: String
    var pairing: String
}
