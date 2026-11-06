import Foundation
import YcodeAssistant
import YcodeIDECore

/// The Swift side of the Reverse bridge: Legacy's
/// `ReverseBridge` (`ReverseBridge.swift`) ported to Ycode.
///
/// One request per process: spawns `node ReverseBridge.mjs
/// --rea-dir <rea-agents@6.5.0 dir>`, writes one NDJSON request
/// line to stdin, closes stdin, and reads stdout to EOF. Stdout
/// carries ONLY protocol frames (progress / result / error), one
/// JSON object per line; diagnostics go to stderr. Nothing is
/// downloaded or installed by the tool.
///
/// Resolution order (Ycode names first, Legacy `SWIFTCODE_*`
/// names kept as aliases):
/// * bridge: `YCODE_REVERSE_BRIDGE_PATH` / `SWIFTCODE_REVERSE_BRIDGE_PATH`
///   env, then the `Bundle.module` resource `ReverseBridge.mjs`
///   (needs the Package.swift resources wiring — without it the
///   tool fails honestly naming the missing resource), then
///   `~/Library/Application Support/Ycode/Reverse/ReverseBridge.mjs`.
/// * REA dir: `YCODE_REVERSE_REA_DIR` / `SWIFTCODE_REVERSE_REA_DIR`
///   env, then `<bridge>/node_modules/rea-agents`, then
///   `~/Library/Application Support/Ycode/Reverse/node_modules/rea-agents`.
///   The directory must contain `package.json` with
///   `name == "rea-agents"` and `version == "6.5.0"`.
/// * Node: `YCODE_NODE_PATH` / `SWIFTCODE_NODE_PATH` env, then
///   `/opt/homebrew/bin/node`, `/usr/local/bin/node`, `/usr/bin/node`,
///   then PATH. The major version must be 22, 24, or 26.
///
/// The child never receives secret-bearing environment variables.
/// Cancellation is the timeout only (the full REA subsystem's
/// manager lifecycle is not ported).
///
/// See `specs/ide/gap-closure-failing-tools.md` §9.
extension YcodeMCPHost {
    /// The pinned REA package and protocol version (the bridge's
    /// `PINNED_REA_VERSION` / `PROTOCOL_VERSION`).
    nonisolated static let reversePinnedREAVersion = "6.5.0"
    nonisolated static let reverseProtocolVersion = 1
    nonisolated static let reverseSupportedNodeMajors: Set<Int> = [22, 24, 26]
    nonisolated static let reverseMaxStdoutBytes = 8_388_608
    nonisolated static let reverseMaxStderrBytes = 65_536

    /// Test seam: replaces the bridge spawn in tests. Receives the
    /// request JSON and returns the bridge stdout text. Nil in
    /// production.
    nonisolated(unsafe) static var reverseBridgeTestRunner: (@Sendable ([String: Any]) async throws -> String)?

    nonisolated static func reverseNonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// Locates the bridge script.
    nonisolated static func reverseResolveBridgeURL() -> URL? {
        let fm = FileManager.default
        for key in ["YCODE_REVERSE_BRIDGE_PATH", "SWIFTCODE_REVERSE_BRIDGE_PATH"] {
            if let candidate = reverseNonEmpty(ProcessInfo.processInfo.environment[key]) {
                let expanded = (candidate as NSString).expandingTildeInPath
                if fm.isReadableFile(atPath: expanded) { return URL(fileURLWithPath: expanded) }
            }
        }
        if let resource = Bundle.module.url(forResource: "ReverseBridge", withExtension: "mjs") {
            return resource
        }
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let url = support.appendingPathComponent("Ycode/Reverse/ReverseBridge.mjs")
            if fm.isReadableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// Locates the pinned `rea-agents` package directory.
    nonisolated static func reverseResolveREADirectory(bridgeURL: URL?) -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        for key in ["YCODE_REVERSE_REA_DIR", "SWIFTCODE_REVERSE_REA_DIR"] {
            if let env = reverseNonEmpty(ProcessInfo.processInfo.environment[key]) {
                candidates.append((env as NSString).expandingTildeInPath)
            }
        }
        if let bridgeURL {
            candidates.append(bridgeURL.deletingLastPathComponent().appendingPathComponent("node_modules/rea-agents").path)
        }
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(support.appendingPathComponent("Ycode/Reverse/node_modules/rea-agents").path)
        }
        for candidate in candidates {
            let packageURL = URL(fileURLWithPath: candidate).appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: packageURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String, name == "rea-agents",
                  let version = json["version"] as? String, version == reversePinnedREAVersion
            else { continue }
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    /// Resolves a Node.js executable without downloading anything.
    nonisolated static func reverseResolveNodeURL() -> URL? {
        let fm = FileManager.default
        func executable(at path: String) -> URL? {
            let expanded = (path as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue,
                  fm.isExecutableFile(atPath: expanded) else { return nil }
            return URL(fileURLWithPath: expanded)
        }
        for key in ["YCODE_NODE_PATH", "SWIFTCODE_NODE_PATH"] {
            if let override = reverseNonEmpty(ProcessInfo.processInfo.environment[key]),
               let url = executable(at: override) { return url }
        }
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] {
            if let url = executable(at: path) { return url }
        }
        if let pathValue = ProcessInfo.processInfo.environment["PATH"] {
            for component in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
                if let url = executable(at: "\(component)/node") { return url }
            }
        }
        return nil
    }

    /// Node major version for a resolved Node binary (`node --version`,
    /// argv only, no shell). Nil when it cannot be determined.
    nonisolated static func reverseNodeMajorVersion(for nodeURL: URL) -> Int? {
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "")
        return text.split(separator: ".").first.flatMap { Int($0) }
    }

    /// Host environment with secret-bearing variables stripped.
    /// The bridge child never receives API keys, tokens,
    /// passwords, or client secrets.
    nonisolated static let reverseSecretEnvNameFragments = [
        "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL",
        "PRIVATE_KEY", "API_KEY", "APIKEY", "ACCESS_KEY",
        "AUTH_TOKEN", "CLIENT_SECRET", "SESSION_TOKEN",
    ]

    nonisolated static func reverseSanitizedEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { name, _ in
            let upper = name.uppercased()
            return !reverseSecretEnvNameFragments.contains { upper.contains($0) }
        }
    }

    /// One bridge protocol frame, decoded from a stdout line.
    struct ReverseBridgeFrame: Sendable {
        var type: String
        var evidence: [String: Any]?
        var error: [String: Any]?
    }

    /// Validates and decodes the bridge stdout frames: every line
    /// must be one protocol frame, version 1, with the request's
    /// id, and a type in progress/result/error. Returns the folded
    /// result: the Evidence dict, or the bridge error dict.
    nonisolated static func reverseParseFrames(_ stdout: String, requestID: String, stderr: String, exitCode: Int32) throws -> [String: Any] {
        var evidence: [String: Any]?
        var bridgeError: [String: Any]?
        var sawFrame = false
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let lineData = Data(line.utf8)
            guard lineData.count <= 1_048_576 else {
                throw MCPToolError("Bridge frame exceeded the 1 MiB limit.")
            }
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let version = obj["version"] as? Int, version == reverseProtocolVersion,
                  let id = obj["id"] as? String, id == requestID,
                  let type = obj["type"] as? String, ["progress", "result", "error"].contains(type) else {
                throw MCPToolError("Bridge sent a malformed protocol frame.\nBridge stderr: \(stderr.prefix(500))")
            }
            sawFrame = true
            if type == "result", let ev = obj["evidence"] as? [String: Any] { evidence = ev }
            if type == "error", let err = obj["error"] as? [String: Any] { bridgeError = err }
        }
        guard sawFrame else {
            throw MCPToolError("Bridge exited (code \(exitCode)) without sending a protocol frame.\nBridge stderr: \(stderr.prefix(500))")
        }
        if let bridgeError {
            let message = bridgeError["message"] as? String ?? "Bridge reported an error."
            let remediation = bridgeError["remediation"] as? String
            throw MCPToolError(message + (remediation.map { "\nRemediation: \($0)" } ?? ""))
        }
        guard let evidence else {
            throw MCPToolError("Bridge completed without returning Evidence or an error.\nBridge stderr: \(stderr.prefix(500))")
        }
        guard let evidenceID = evidence["evidence_id"] as? String, !evidenceID.isEmpty,
              let operation = evidence["operation"] as? String, !operation.isEmpty else {
            throw MCPToolError("Bridge returned a payload without a valid Evidence envelope (missing evidence_id or operation).")
        }
        return evidence
    }

    /// Runs one `analyze` request through the bridge and returns
    /// the Evidence dict. Throws `MCPToolError` naming exactly
    /// which piece is missing (bridge, REA dir, Node, version) and
    /// how to supply it.
    func reverseBridgeAnalyze(operation: String, targetPath: String, objdumpOperation: String?,
                              symbol: String?, timeout: TimeInterval) async throws -> [String: Any] {
        let requestID = UUID().uuidString
        var params: [String: Any] = ["operation": operation, "targetPath": targetPath]
        if let objdumpOperation { params["objdumpOperation"] = objdumpOperation }
        if let symbol, !symbol.isEmpty { params["symbol"] = symbol }
        let request: [String: Any] = ["version": Self.reverseProtocolVersion, "id": requestID,
                                      "method": "analyze", "params": params]
        if let runner = Self.reverseBridgeTestRunner {
            let stdout = try await runner(request)
            return try Self.reverseParseFrames(stdout, requestID: requestID, stderr: "", exitCode: 0)
        }
        guard let bridgeURL = Self.reverseResolveBridgeURL() else {
            throw MCPToolError("Reverse bridge script (ReverseBridge.mjs) was not found.\nRemediation: Set YCODE_REVERSE_BRIDGE_PATH (or SWIFTCODE_REVERSE_BRIDGE_PATH) to the bridge script, or reinstall Ycode so the bundled bridge resource is present (the YcodeMCP target needs the Resources/ReverseBridge.mjs wiring in Package.swift). Reverse is unavailable until then.")
        }
        guard let reaDir = Self.reverseResolveREADirectory(bridgeURL: bridgeURL) else {
            throw MCPToolError("The pinned REA package (rea-agents@\(Self.reversePinnedREAVersion)) was not found.\nRemediation: Set YCODE_REVERSE_REA_DIR (or SWIFTCODE_REVERSE_REA_DIR) to a folder containing rea-agents@\(Self.reversePinnedREAVersion) (for example: npm install rea-agents@\(Self.reversePinnedREAVersion) into a directory and point the variable at it). Ycode never downloads or installs it automatically.")
        }
        guard let nodeURL = Self.reverseResolveNodeURL() else {
            throw MCPToolError("Node.js was not found.\nRemediation: Install Node.js 22, 24, or 26 (REA \(Self.reversePinnedREAVersion) engines) from nodejs.org or Homebrew, or set YCODE_NODE_PATH (or SWIFTCODE_NODE_PATH) to a Node binary.")
        }
        let major = await Task.detached { Self.reverseNodeMajorVersion(for: nodeURL) }.value
        if let major, !Self.reverseSupportedNodeMajors.contains(major) {
            throw MCPToolError("Node.js v\(major) is not supported by REA \(Self.reversePinnedREAVersion).\nRemediation: Use Node.js 22, 24, or 26.")
        }
        let requestData = try JSONSerialization.data(withJSONObject: request)
        let (stdout, stderr, exitCode, timedOut) = try await Self.reverseSpawn(
            nodeURL: nodeURL, bridgeURL: bridgeURL, reaDir: reaDir,
            requestData: requestData, timeout: timeout)
        if timedOut {
            throw MCPToolError("Reverse operation timed out after \(Int(timeout))s and the bridge process was terminated.\nRemediation: Retry with a smaller target, or raise timeoutSeconds.")
        }
        return try Self.reverseParseFrames(String(decoding: stdout, as: UTF8.self), requestID: requestID,
                                           stderr: stderr, exitCode: exitCode)
    }

    /// Spawns `node <bridge> --rea-dir <reaDir>`, writes the
    /// request to stdin, closes stdin, and reads stdout to EOF
    /// (bounded at 8 MiB; stderr at 64 KiB). The timeout kills the
    /// child. Returns stdout, stderr, exit code, and whether the
    /// timeout fired.
    nonisolated static func reverseSpawn(nodeURL: URL, bridgeURL: URL, reaDir: URL,
                                         requestData: Data, timeout: TimeInterval) async throws -> (Data, String, Int32, Bool) {
        try await Task.detached {
            let process = Process()
            process.executableURL = nodeURL
            process.arguments = [bridgeURL.path, "--rea-dir", reaDir.path]
            process.environment = reverseSanitizedEnvironment()
            let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = inPipe
            let lock = NSLock()
            var stdoutData = Data()
            var stderrData = Data()
            var stdoutOverflow = false
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock(); defer { lock.unlock() }
                stdoutData.append(chunk)
                if stdoutData.count > reverseMaxStdoutBytes {
                    stdoutOverflow = true
                    stdoutData.removeFirst(stdoutData.count - reverseMaxStdoutBytes)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock(); defer { lock.unlock() }
                stderrData.append(chunk)
                if stderrData.count > reverseMaxStderrBytes {
                    stderrData.removeFirst(stderrData.count - reverseMaxStderrBytes)
                }
            }
            do { try process.run() } catch {
                throw MCPToolError("Could not start Node for the Reverse bridge (\(nodeURL.path)): \(error.localizedDescription)")
            }
            inPipe.fileHandleForWriting.write(requestData)
            inPipe.fileHandleForWriting.write(Data([0x0A]))
            try? inPipe.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(timeout)
            var timedOut = false
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning {
                timedOut = true
                process.terminate()
                try? await Task.sleep(nanoseconds: 200_000_000)
                if process.isRunning { process.interrupt() }
            }
            process.waitUntilExit()
            // Let the pipe handlers drain the final bytes.
            try? await Task.sleep(nanoseconds: 100_000_000)
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let (stdout, stderr) = lock.withLock { (stdoutData, String(decoding: stderrData, as: UTF8.self)) }
            if stdoutOverflow {
                throw MCPToolError("Bridge output exceeded the 8 MiB limit.")
            }
            return (stdout, stderr, process.terminationStatus, timedOut)
        }.value
    }

    // MARK: - Evidence rendering

    /// Renders an Evidence dict as Markdown: id, operation,
    /// provider, confidence, findings/sections when present, else
    /// pretty JSON (capped at 8,000 characters).
    nonisolated static func reverseRenderEvidence(_ evidence: [String: Any]) -> String {
        var lines: [String] = []
        let id = evidence["evidence_id"] as? String ?? ""
        let operation = evidence["operation"] as? String ?? ""
        lines.append("# Reverse Evidence: \(operation)")
        lines.append("")
        lines.append("- evidence_id: \(id)")
        if let provider = evidence["provider"] as? String { lines.append("- provider: \(provider)") }
        if let confidence = evidence["confidence"] {
            lines.append("- confidence: \(String(describing: confidence))")
        }
        if let subject = evidence["subject_digest"] as? String { lines.append("- subject: \(subject)") }
        for key in ["findings", "sections"] {
            if let items = evidence[key] as? [[String: Any]], !items.isEmpty {
                lines.append("")
                lines.append("## \(key.capitalized)")
                for item in items {
                    let title = item["title"] as? String ?? item["name"] as? String ?? ""
                    let body = item["summary"] as? String ?? item["text"] as? String ?? item["description"] as? String ?? ""
                    if title.isEmpty && body.isEmpty { continue }
                    lines.append("- \(title.isEmpty ? "" : "**\(title)**: ")\(body)")
                }
            }
        }
        if lines.count <= 6 {
            if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                lines.append("")
                lines.append("```json")
                lines.append(String(json.prefix(8_000)))
                lines.append("```")
            }
        }
        return lines.joined(separator: "\n")
    }
}
