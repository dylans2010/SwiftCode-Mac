import Foundation

/// Dedicated native entry point for macOS system diagnostics and one
/// narrowly-scoped, authorized user-level configuration operation.
///
/// Finite operation set, selected by the required `operation` parameter.
/// Read-only diagnostics (`system_info`, `dev_environment`, `process_list`,
/// `network_interfaces`, `listening_sockets`, `connectivity`, `disk_info`,
/// `system_log`, `service_status`, `config_read`) gather real state through
/// Darwin/Foundation APIs and fixed-argv subprocesses — never a shell.
///
/// The single mutation, `user_defaults_write`, exercises the full
/// validate -> authorize -> explain -> perform -> capture -> verify flow:
/// the domain/key/value are validated, the model must pass
/// `confirm: true`, the write goes through fixed-argv `/usr/bin/defaults`,
/// and the new value is read back with `defaults read` and compared before
/// the tool reports success. A read-back mismatch is reported as failure.
///
/// Nothing here runs as root, touches SIP/TCC, or accepts arbitrary
/// commands. Anything requiring privileges (TCC-gated log access, other
/// users' sockets, admin-only daemons) is reported honestly with
/// `permissionDenied`/`unsupportedOperation` — escalation is never
/// attempted.
public struct AssistSystemTool: AssistTool {
    public let id = "use_system"
    public let name = "System Diagnostics"
    public let description = "macOS system diagnostics and one authorized user-level configuration op. Diagnostics: system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read (sysctl allowlist). Mutation: user_defaults_write (requires confirm: true; verified by read-back). Fixed-argv subprocesses only; privileged actions are refused, never escalated."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs one macOS system-diagnostics operation, or the single authorized user-level mutation (user_defaults_write).",
            properties: [
                "operation": JSONSchema(
                    type: "string",
                    description: "One of: system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read, user_defaults_write."
                ),
                "target": JSONSchema(
                    type: "string",
                    description: "Operation-dependent: process name filter (process_list), interface name (network_interfaces), hostname (connectivity), sysctl name (config_read, must be on the allowlist), defaults domain (user_defaults_write)."
                ),
                "parameters": JSONSchema(
                    type: "object",
                    description: "Per-operation options.",
                    properties: [
                        "port": JSONSchema(type: "integer", description: "TCP port for connectivity (1-65535, required)."),
                        "timeoutSeconds": JSONSchema(type: "number", description: "Timeout for connectivity in seconds (default 5, max 30)."),
                        "limit": JSONSchema(type: "integer", description: "Max rows for process_list (default 50, capped at 200)."),
                        "filter": JSONSchema(type: "string", description: "Name filter for process_list (also accepted via target)."),
                        "predicate": JSONSchema(type: "string", description: "NSPredicate string for system_log (e.g. 'process == \"kernel\"')."),
                        "minutes": JSONSchema(type: "integer", description: "Lookback window for system_log in minutes (1-60, default 15)."),
                        "domain": JSONSchema(type: "string", description: "Defaults domain for user_defaults_write (also accepted via target)."),
                        "key": JSONSchema(type: "string", description: "Defaults key for user_defaults_write (required)."),
                        "value": JSONSchema(type: "string", description: "Value for user_defaults_write (string, number, or boolean; required).")
                    ]
                ),
                "confirm": JSONSchema(
                    type: "boolean",
                    description: "Required true for user_defaults_write; the model must explicitly confirm the mutation."
                )
            ],
            required: ["operation"]
        )
    }

    // MARK: - Limits

    /// Hard cap for subprocess stdout captured into the result; the canonical
    /// truncation marker is appended whenever it is exceeded.
    private static let outputCap = 8_000
    private static let devEnvironmentTimeout: TimeInterval = 60
    private static let quickTimeout: TimeInterval = 15
    private static let logTimeout: TimeInterval = 45
    private static let defaultsTimeout: TimeInterval = 10

    /// sysctl names the model may read, with the expected value kind.
    private enum SysctlKind { case string, int32, uint64 }
    private static let sysctlAllowlist: [String: SysctlKind] = [
        "kern.ostype": .string,
        "kern.osrelease": .string,
        "kern.osrevision": .string,
        "kern.version": .string,
        "kern.hostname": .string,
        "kern.maxproc": .int32,
        "hw.model": .string,
        "hw.machine": .string,
        "hw.ncpu": .int32,
        "hw.physicalmem": .uint64,
        "hw.memsize": .uint64,
        "hw.memsize_usable": .uint64,
        "hw.cpufrequency": .uint64,
        "machdep.cpu.brand_string": .string
    ]

    /// Domains that are never writable through this tool: the global domain
    /// affects every app, and anything outside the user domain (paths, the
    /// system /Library) is out of scope.
    private static let blockedDomains: Set<String> = ["NSGlobalDomain"]

    // MARK: - Execute

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let operation = input["operation"] as? String, !operation.isEmpty else {
            return .failure("Missing required parameter: operation", code: .missingArgument)
        }
        let target = input["target"] as? String
        let params = input["parameters"] as? [String: Any] ?? [:]

        switch operation {
        case "system_info":
            return opSystemInfo()
        case "dev_environment":
            return await opDevEnvironment(context: context)
        case "process_list":
            let filter = params["filter"] as? String ?? target
            let limit = clampedInt(params["limit"], default: 50, min: 1, max: 200)
            return await opProcessList(filter: filter, limit: limit, context: context)
        case "network_interfaces":
            return await opNetworkInterfaces(interface: target, context: context)
        case "listening_sockets":
            return await opListeningSockets(context: context)
        case "connectivity":
            return await opConnectivity(target: target, params: params)
        case "disk_info":
            return opDiskInfo()
        case "system_log":
            let minutes = clampedInt(params["minutes"], default: 15, min: 1, max: 60)
            return await opSystemLog(predicate: params["predicate"] as? String, minutes: minutes, context: context)
        case "service_status":
            return await opServiceStatus(context: context)
        case "config_read":
            guard let name = target, !name.isEmpty else {
                return .failure("Missing required target: sysctl name (must be one of the allowlisted names)", code: .missingArgument)
            }
            return opConfigRead(name: name)
        case "user_defaults_write":
            guard input["confirm"] as? Bool == true else {
                return .failure(
                    "user_defaults_write requires explicit confirmation: re-run with confirm: true, plus target/domain, parameters.key, and parameters.value",
                    code: .missingArgument
                )
            }
            return await opUserDefaultsWrite(target: target, params: params, context: context)
        default:
            let supported = ["system_info", "dev_environment", "process_list", "network_interfaces", "listening_sockets", "connectivity", "disk_info", "system_log", "service_status", "config_read", "user_defaults_write"]
            return .failure("Unknown operation '\(operation)'. Supported: \(supported.joined(separator: ", "))", code: .unsupportedOperation)
        }
    }

    // MARK: - Helpers

    /// Caps tool output at `outputCap` characters with the canonical
    /// truncation marker; returns the (possibly capped) text and whether it
    /// was capped.
    private func cappedOutput(_ output: String) -> (String, Bool) {
        guard output.count > Self.outputCap else { return (output, false) }
        // output: truncated head; canonical marker appended so the model
        // never mistakes a cut payload for a complete one.
        let head = String(output.prefix(Self.outputCap))
        return (head + "\n…[truncated: output exceeded \(Self.outputCap) characters]", true)
    }

    private func clampedInt(_ value: Any?, default def: Int, min lo: Int, max hi: Int) -> Int {
        var v = def
        if let i = value as? Int { v = i }
        else if let d = value as? Double { v = Int(d) }
        else if let s = value as? String, let i = Int(s) { v = i }
        return Swift.min(Swift.max(v, lo), hi)
    }

    private func matches(_ text: String, pattern: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, range: range) != nil
    }

    private func cStringField(_ field: Any) -> String {
        var bytes: [CChar] = []
        for child in Mirror(reflecting: field).children {
            guard let b = child.value as? CChar, b != 0 else { break }
            bytes.append(b)
        }
        bytes.append(0)
        return String(cString: bytes)
    }

    /// Runs a fixed system binary via the sanctioned argv runner. Never a
    /// shell: arguments are passed as argv elements only.
    private func runFixed(_ path: String, _ args: [String], timeout: TimeInterval, context: AssistContext) async -> AssistArgvRunner.Result? {
        let start = Date()
        do {
            let result = try AssistArgvRunner.run(
                executableURL: URL(fileURLWithPath: path),
                arguments: args,
                workingDirectory: context.workspaceRoot,
                timeout: timeout
            )
            let elapsed = Date().timeIntervalSince(start)
            await context.logger.info(
                "use_system ran \(path) \(args.joined(separator: " ")) -> exit \(result.exitCode)\(result.timedOut ? " (timed out)" : "") in \(Int(elapsed * 1000))ms",
                toolId: id
            )
            return result
        } catch {
            await context.logger.error("use_system failed to launch \(path): \(error.localizedDescription)")
            return nil
        }
    }

    private func permissionDeniedIn(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("permission denied") ||
        text.localizedCaseInsensitiveContains("not permitted") ||
        text.localizedCaseInsensitiveContains("operation not permitted")
    }

    // MARK: - Diagnostics

    private func opSystemInfo() -> AssistToolResult {
        let info = ProcessInfo.processInfo
        let v = info.operatingSystemVersion
        var uts = utsname()
        uname(&uts)
        let release = cStringField(uts.release)
        let machine = cStringField(uts.machine)
        let hostname = info.hostName
        let uptimeSeconds = Int(info.systemUptime)
        let lines = [
            "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion) (Darwin \(release))",
            "Architecture: \(machine)",
            "Hostname: \(hostname)",
            "CPU count: \(info.processorCount)",
            "Physical memory: \(info.physicalMemory) bytes",
            "System uptime: \(uptimeSeconds) seconds"
        ]
        return .success(lines.joined(separator: "\n"), data: [
            "operation": "system_info",
            "osVersion": "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            "osBuild": release,
            "arch": machine,
            "hostname": hostname,
            "cpuCount": "\(info.processorCount)",
            "physicalMemoryBytes": "\(info.physicalMemory)",
            "uptimeSeconds": "\(uptimeSeconds)",
            "content": lines.joined(separator: "\n")
        ])
    }

    private func opDevEnvironment(context: AssistContext) async -> AssistToolResult {
        var sections: [String] = []
        // Each probe is a fixed binary + fixed argv; a missing tool is
        // reported, not fabricated.
        let probes: [(label: String, path: String, args: [String])] = [
            ("xcodebuild", "/usr/bin/xcodebuild", ["-version"]),
            ("swift", "/usr/bin/swift", ["--version"]),
            ("xcrun swift", "/usr/bin/xcrun", ["--find", "swift"])
        ]
        for probe in probes {
            guard let result = await runFixed(probe.path, probe.args, timeout: Self.devEnvironmentTimeout, context: context) else {
                sections.append("## \(probe.label)\nnot available: failed to launch \(probe.path)")
                continue
            }
            if result.timedOut {
                return .failure("\(probe.label) probe timed out after \(Int(Self.devEnvironmentTimeout))s", code: .timeout)
            }
            let (text, wasTruncated) = cappedOutput(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            sections.append("## \(probe.label) (exit \(result.exitCode))\(wasTruncated ? " [truncated]" : "")\n\(text.isEmpty ? "(no output)" : text)")
        }
        let content = sections.joined(separator: "\n\n")
        return .success(content, data: [
            "operation": "dev_environment",
            "tools": "xcodebuild,swift,xcrun",
            "content": content
        ])
    }

    private func opProcessList(filter: String?, limit: Int, context: AssistContext) async -> AssistToolResult {
        guard let result = await runFixed("/bin/ps", ["-eo", "pid,pcpu,pmem,comm"], timeout: Self.quickTimeout, context: context) else {
            return .failure("Failed to launch /bin/ps", code: .executionFailed)
        }
        if result.timedOut {
            return .failure("process listing timed out after \(Int(Self.quickTimeout))s", code: .timeout)
        }
        if result.exitCode != 0 {
            if permissionDeniedIn(result.output) {
                return .failure("process listing denied by the OS: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", code: .permissionDenied)
            }
            return .failure("/bin/ps exited \(result.exitCode): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", code: .executionFailed)
        }
        var rows: [String] = []
        for line in result.output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("PID") { continue }
            if let f = filter, !f.isEmpty, !trimmed.localizedCaseInsensitiveContains(f) { continue }
            rows.append(trimmed)
        }
        let shown = Array(rows.prefix(limit))
        var content = shown.joined(separator: "\n")
        if rows.count > limit {
            content += "\n…[truncated: showing \(limit) of \(rows.count) matching processes]"
        }
        if content.isEmpty {
            content = "No processes matched\(filter.map { " filter '\($0)'" } ?? "")."
        }
        return .success(content, data: [
            "operation": "process_list",
            "filter": filter ?? "",
            "count": "\(rows.count)",
            "truncated": "\(rows.count > limit)",
            "content": content
        ])
    }

    private func opNetworkInterfaces(interface: String?, context: AssistContext) async -> AssistToolResult {
        var args: [String] = []
        if let name = interface, !name.isEmpty {
            guard matches(name, pattern: "^[A-Za-z0-9._-]+$") else {
                return .failure("Invalid interface name '\(name)'", code: .invalidInput)
            }
            args = [name]
        }
        guard let result = await runFixed("/sbin/ifconfig", args, timeout: Self.quickTimeout, context: context) else {
            return .failure("Failed to launch /sbin/ifconfig", code: .executionFailed)
        }
        if result.timedOut {
            return .failure("interface listing timed out after \(Int(Self.quickTimeout))s", code: .timeout)
        }
        if result.exitCode != 0 {
            if permissionDeniedIn(result.output) {
                return .failure("interface listing denied by the OS", code: .permissionDenied)
            }
            return .failure("/sbin/ifconfig exited \(result.exitCode): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", code: .executionFailed)
        }
        let (content, wasTruncated) = cappedOutput(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        return .success(content, data: [
            "operation": "network_interfaces",
            "interface": interface ?? "",
            "truncated": "\(wasTruncated)",
            "content": content
        ])
    }

    private func opListeningSockets(context: AssistContext) async -> AssistToolResult {
        guard let result = await runFixed("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-P", "-n"], timeout: 20, context: context) else {
            return .failure("Failed to launch /usr/sbin/lsof", code: .executionFailed)
        }
        if result.timedOut {
            return .failure("socket listing timed out after 20s", code: .timeout)
        }
        if result.exitCode != 0 {
            if permissionDeniedIn(result.output) {
                // lsof cannot inspect other users' sockets without privileges;
                // we report that honestly instead of attempting escalation.
                return .failure("lsof was denied access to socket information (requires privileges this tool will not request). Output so far: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", code: .permissionDenied)
            }
            if result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .success("No TCP listeners found.")
            }
            return .failure("/usr/sbin/lsof exited \(result.exitCode): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", code: .executionFailed)
        }
        let (content, wasTruncated) = cappedOutput(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        return .success(content.isEmpty ? "No TCP listeners found." : content, data: [
            "operation": "listening_sockets",
            "count": "\(content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count)",
            "truncated": "\(wasTruncated)",
            "content": content
        ])
    }

    private func opConnectivity(target: String?, params: [String: Any]) async -> AssistToolResult {
        guard let host = target, !host.isEmpty else {
            return .failure("Missing required target: hostname or IP address to connect to", code: .missingArgument)
        }
        guard let port = clampedIntOptional(params["port"]), (1...65535).contains(port) else {
            return .failure("Missing or invalid parameters.port (must be 1-65535)", code: .missingArgument)
        }
        let timeout = clampedDouble(params["timeoutSeconds"], default: 5, min: 1, max: 30)
        let start = Date()
        // Blocking POSIX connect/select runs off the main actor; execute()
        // is @MainActor and must never stall the UI thread.
        let reachable = await Task.detached(priority: .utility) {
            self.tcpConnect(host: host, port: port, timeoutSeconds: timeout)
        }.value
        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        let verdict = reachable ? "reachable" : "not reachable"
        let content = "TCP \(host):\(port) — \(verdict) (\(latencyMs)ms, timeout \(Int(timeout))s)"
        return .success(content, data: [
            "operation": "connectivity",
            "host": host,
            "port": "\(port)",
            "reachable": "\(reachable)",
            "latencyMs": "\(latencyMs)",
            "content": content
        ])
    }

    private func opDiskInfo() -> AssistToolResult {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity else {
            return .failure("Could not read volume capacity for /", code: .executionFailed)
        }
        let used = total - available
        let usedPercent = total > 0 ? Double(used) / Double(total) * 100.0 : 0.0
        let name = values.volumeName ?? "/"
        let content = [
            "Volume: \(name) (/)",
            "Total: \(total) bytes",
            "Available: \(available) bytes",
            "Used: \(used) bytes (\(String(format: "%.1f", usedPercent))%)"
        ].joined(separator: "\n")
        return .success(content, data: [
            "operation": "disk_info",
            "path": "/",
            "totalBytes": "\(total)",
            "availableBytes": "\(available)",
            "usedBytes": "\(used)",
            "usedPercent": String(format: "%.1f", usedPercent),
            "content": content
        ])
    }

    private func opSystemLog(predicate: String?, minutes: Int, context: AssistContext) async -> AssistToolResult {
        var args = ["show", "--style", "compact", "--last", "\(minutes)m"]
        if let p = predicate, !p.isEmpty {
            args += ["--predicate", p]
        }
        guard let result = await runFixed("/usr/bin/log", args, timeout: Self.logTimeout, context: context) else {
            return .failure("Failed to launch /usr/bin/log", code: .executionFailed)
        }
        if result.timedOut {
            return .failure("system log query timed out after \(Int(Self.logTimeout))s; narrow with a predicate or fewer minutes", code: .timeout)
        }
        if result.exitCode != 0 {
            if permissionDeniedIn(result.output) {
                return .failure("Reading the system log was denied by the OS (logd/TCC). This tool does not request elevated access.", code: .permissionDenied)
            }
            return .failure("/usr/bin/log exited \(result.exitCode): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", code: .executionFailed)
        }
        let (content, wasTruncated) = cappedOutput(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        let lineCount = content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        return .success(content.isEmpty ? "No log entries in the last \(minutes) minute(s)." : content, data: [
            "operation": "system_log",
            "predicate": predicate ?? "",
            "minutes": "\(minutes)",
            "count": "\(lineCount)",
            "truncated": "\(wasTruncated)",
            "content": content
        ])
    }

    private func opServiceStatus(context: AssistContext) async -> AssistToolResult {
        // Read-only listing of the user's launchd domain. No load/unload —
        // that would change system state and is out of scope.
        guard let result = await runFixed("/bin/launchctl", ["list"], timeout: Self.quickTimeout, context: context) else {
            return .failure("Failed to launch /bin/launchctl", code: .executionFailed)
        }
        if result.timedOut {
            return .failure("service listing timed out after \(Int(Self.quickTimeout))s", code: .timeout)
        }
        if result.exitCode != 0 {
            if permissionDeniedIn(result.output) {
                return .failure("Reading launchd services was denied by the OS", code: .permissionDenied)
            }
            return .failure("/bin/launchctl exited \(result.exitCode): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", code: .executionFailed)
        }
        let (content, wasTruncated) = cappedOutput(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        let rows = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // First row is the header; the rest are services.
        let serviceCount = max(0, rows.count - 1)
        return .success(content, data: [
            "operation": "service_status",
            "count": "\(serviceCount)",
            "truncated": "\(wasTruncated)",
            "content": content
        ])
    }

    private func opConfigRead(name: String) -> AssistToolResult {
        guard matches(name, pattern: "^[a-z0-9._]+$"), let kind = Self.sysctlAllowlist[name] else {
            return .failure(
                "sysctl '\(name)' is not on the allowlist. Allowed: \(Self.sysctlAllowlist.keys.sorted().joined(separator: ", "))",
                code: .invalidInput
            )
        }
        guard let value = readSysctl(name, kind: kind) else {
            return .failure("sysctlbyname failed for '\(name)'", code: .executionFailed)
        }
        return .success("\(name) = \(value)", data: [
            "operation": "config_read",
            "sysctlName": name,
            "value": value,
            "content": "\(name) = \(value)"
        ])
    }

    // MARK: - Mutation: user_defaults_write

    private func opUserDefaultsWrite(target: String?, params: [String: Any], context: AssistContext) async -> AssistToolResult {
        let domain = (params["domain"] as? String) ?? target
        guard let domain = domain, !domain.isEmpty else {
            return .failure("Missing required target/domain for user_defaults_write", code: .missingArgument)
        }
        guard matches(domain, pattern: "^[A-Za-z0-9.-]+$"), !domain.contains("..") else {
            return .failure("Invalid defaults domain '\(domain)': must match ^[A-Za-z0-9.-]+$", code: .invalidInput)
        }
        if Self.blockedDomains.contains(where: { $0.caseInsensitiveCompare(domain) == .orderedSame }) {
            return .failure(
                "Domain '\(domain)' is blocked: writing the global domain affects every application and is out of scope for this tool. Choose the app's own domain (e.g. com.example.MyApp).",
                code: .permissionDenied
            )
        }
        guard let key = params["key"] as? String, !key.isEmpty else {
            return .failure("Missing required parameters.key for user_defaults_write", code: .missingArgument)
        }
        guard matches(key, pattern: "^[A-Za-z0-9._-]+$") else {
            return .failure("Invalid parameters.key '\(key)': must match ^[A-Za-z0-9._-]+$", code: .invalidInput)
        }
        guard let rawValue = params["value"] else {
            return .failure("Missing required parameters.value (string, number, or boolean)", code: .missingArgument)
        }
        // defaults write needs a typed flag; only scalar JSON types allowed.
        let writeArgs: [String]
        let expectedReadback: String
        if let b = rawValue as? Bool {
            writeArgs = ["-bool", b ? "YES" : "NO"]
            expectedReadback = b ? "1" : "0"
        } else if let s = rawValue as? String {
            writeArgs = [s]
            expectedReadback = s
        } else if let n = rawValue as? NSNumber {
            // NSNumber covers Int/Double from JSON; Bool was handled above.
            if n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 9_000_000_000_000_000 {
                writeArgs = ["-int", "\(n.intValue)"]
                expectedReadback = "\(n.intValue)"
            } else {
                writeArgs = ["-float", "\(n.doubleValue)"]
                expectedReadback = "\(n.doubleValue)"
            }
        } else {
            return .failure("parameters.value must be a string, number, or boolean (objects, arrays, and null are rejected)", code: .invalidInput)
        }

        // Capture the previous value so the report can show before/after.
        let before = await defaultsRead(domain: domain, key: key, context: context)
        let previousDisplay = before ?? "<not set>"

        // Perform the write (user domain only; defaults never touches
        // /Library or SIP-protected locations from here).
        guard let writeResult = await runFixed("/usr/bin/defaults", ["write", domain, key] + writeArgs, timeout: Self.defaultsTimeout, context: context) else {
            return .failure("Failed to launch /usr/bin/defaults", code: .executionFailed)
        }
        if writeResult.timedOut {
            return .failure("defaults write timed out after \(Int(Self.defaultsTimeout))s", code: .timeout)
        }
        if writeResult.exitCode != 0 {
            return .failure("defaults write failed (exit \(writeResult.exitCode)): \(writeResult.output.trimmingCharacters(in: .whitespacesAndNewlines))", code: .executionFailed)
        }

        // Verify by reading back; a mismatch means the write did not take.
        guard let readback = await defaultsRead(domain: domain, key: key, context: context) else {
            return .failure("defaults write reported success but the value could not be read back (before: \(previousDisplay))", code: .executionFailed)
        }
        guard readback == expectedReadback else {
            return .failure(
                "Verification failed: expected '\(expectedReadback)' after write, read back '\(readback)' (before: \(previousDisplay)). The write did not take effect.",
                code: .executionFailed
            )
        }
        let content = "defaults write \(domain) \(key): '\(previousDisplay)' -> '\(readback)' (verified by read-back)"
        return .success(content, data: [
            "operation": "user_defaults_write",
            "domain": domain,
            "key": key,
            "previousValue": previousDisplay,
            "newValue": readback,
            "verified": "true",
            "content": content
        ])
    }

    /// Reads one key from a user-domain defaults domain. Returns nil when the
    /// key (or domain) does not exist or the read fails.
    private func defaultsRead(domain: String, key: String, context: AssistContext) async -> String? {
        guard let result = await runFixed("/usr/bin/defaults", ["read", domain, key], timeout: Self.defaultsTimeout, context: context),
              !result.timedOut, result.exitCode == 0 else {
            return nil
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Native Darwin helpers

    private func readSysctl(_ name: String, kind: SysctlKind) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        switch kind {
        case .string:
            var buffer = [CChar](repeating: 0, count: size + 1)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
            return String(cString: buffer)
        case .int32:
            var value: Int32 = 0
            var len = MemoryLayout<Int32>.size
            guard sysctlbyname(name, &value, &len, nil, 0) == 0 else { return nil }
            return "\(value)"
        case .uint64:
            var value: UInt64 = 0
            var len = MemoryLayout<UInt64>.size
            guard sysctlbyname(name, &value, &len, nil, 0) == 0 else { return nil }
            return "\(value)"
        }
    }

    /// Bounded TCP connect using POSIX sockets: non-blocking connect +
    /// select() with the requested timeout. No unbounded waits.
    private func tcpConnect(host: String, port: Int, timeoutSeconds: TimeInterval) -> Bool {
        var hints = addrinfo()
        hints.ai_socktype = Int32(SOCK_STREAM)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "\(port)", &hints, &info) == 0, let list = info else { return false }
        defer { freeaddrinfo(list) }
        let fd = socket(list.pointee.ai_family, list.pointee.ai_socktype, list.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        guard let aiAddr = list.pointee.ai_addr else { return false }
        let rc = Darwin.connect(fd, aiAddr, list.pointee.ai_addrlen)
        if rc == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var writeSet = fd_set()
        FD_ZERO(&writeSet)
        FD_SET(fd, &writeSet)
        var tv = timeval(tv_sec: Int(timeoutSeconds), tv_usec: Int32((timeoutSeconds.truncatingRemainder(dividingBy: 1)) * 1_000_000))
        let ready = select(fd + 1, nil, &writeSet, nil, &tv)
        guard ready > 0 else { return false }
        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 else { return false }
        return soError == 0
    }

    private func clampedIntOptional(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private func clampedDouble(_ value: Any?, default def: Double, min lo: Double, max hi: Double) -> Double {
        var v = def
        if let d = value as? Double { v = d }
        else if let i = value as? Int { v = Double(i) }
        else if let s = value as? String, let d = Double(s) { v = d }
        return Swift.min(Swift.max(v, lo), hi)
    }
}
