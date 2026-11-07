import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct ReverseBridgeOutcome: Sendable {
    public let progress: [ReverseProgressEvent]
    public let evidence: ReverseEvidence?
    public let error: ReverseError?
    public let stderrTail: String

    public init(progress: [ReverseProgressEvent], evidence: ReverseEvidence?, error: ReverseError?, stderrTail: String) {
        self.progress = progress
        self.evidence = evidence
        self.error = error
        self.stderrTail = stderrTail
    }
}

public final class ReverseBridge: @unchecked Sendable {
    public static let maxFrameBytes = 1_048_576
    public static let maxStdoutBytes = 8_388_608
    public static let maxStderrBytes = 65_536

    private let lock = NSLock()
    private var running: [String: ProcessBox] = [:]
    private var cancelledIDs: Set<String> = []

    public init() {}

    public func ping() async -> ReversePingInfo? {
        let request = ReverseBridgeRequest(id: UUID().uuidString, method: "ping", params: nil)
        do {
            let (messages, _) = try await runMessages(request: request, timeoutSeconds: 30)
            return messages.first?.ping
        } catch {
            return nil
        }
    }

    public func capabilities() async throws -> [ReverseCapability] {
        let request = ReverseBridgeRequest(id: UUID().uuidString, method: "capabilities", params: nil)
        let (messages, _) = try await runMessages(request: request, timeoutSeconds: 30)
        guard let message = messages.first else {
            throw ReverseError(category: .bridgeFailure, code: "reverse_no_response", message: "Bridge returned no capability frame.", retryable: false)
        }
        if let payload = message.error {
            throw ReverseError.fromBridgePayload(payload)
        }
        return message.capabilities ?? ReverseOperation.allCases.map {
            ReverseCapability(operation: $0, available: false, unavailableReason: "Bridge returned no capability list")
        }
    }

    public func analyze(
        operation: ReverseOperation,
        targetPath: String,
        objdumpOperation: ReverseObjdumpOperation?,
        symbol: String?,
        task: String,
        timeoutSeconds: TimeInterval,
        requestID: String
    ) async throws -> ReverseBridgeOutcome {
        let request = ReverseBridgeRequest(
            id: requestID,
            method: "analyze",
            params: ReverseBridgeParams(
                operation: operation.rawValue,
                targetPath: targetPath,
                objdumpOperation: objdumpOperation?.rawValue,
                symbol: symbol,
                task: task,
                followDebugLinks: false
            )
        )
        return try await run(request: request, timeoutSeconds: timeoutSeconds)
    }

    public func cancel(requestID: String) {
        let box = lock.withLock { () -> ProcessBox? in
            let b = running[requestID]
            if b != nil {
                cancelledIDs.insert(requestID)
            }
            return b
        }
        box?.process?.terminate()
        if let box {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                guard let process = box.process, process.isRunning else { return }
                #if canImport(Darwin)
                kill(process.processIdentifier, SIGKILL)
                #endif
            }
        }
    }

    public func wasCancelled(_ requestID: String) -> Bool {
        lock.withLock {
            cancelledIDs.contains(requestID)
        }
    }

    public static func resolveBridgeURL() -> URL? {
        let fm = FileManager.default
        let candidates: [String?] = [
            nonEmpty(UserDefaults.standard.string(forKey: "assist.reverseBridgePath")),
            nonEmpty(ProcessInfo.processInfo.environment["SWIFTCODE_REVERSE_BRIDGE_PATH"]),
        ]
        for candidate in candidates {
            if let candidate {
                let expanded = (candidate as NSString).expandingTildeInPath
                if fm.isReadableFile(atPath: expanded) {
                    return URL(fileURLWithPath: expanded)
                }
            }
        }
        if let resource = Bundle.main.url(forResource: "ReverseBridge", withExtension: "mjs") {
            return resource
        }
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let url = support.appendingPathComponent("SwiftCode/Reverse/ReverseBridge.mjs")
            if fm.isReadableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    public static func resolveREADirectory(bridgeURL: URL?) -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let override = nonEmpty(UserDefaults.standard.string(forKey: "assist.reverseReaDir")) {
            candidates.append((override as NSString).expandingTildeInPath)
        }
        if let env = nonEmpty(ProcessInfo.processInfo.environment["SWIFTCODE_REVERSE_REA_DIR"]) {
            candidates.append((env as NSString).expandingTildeInPath)
        }
        if let bridgeURL {
            candidates.append(bridgeURL.deletingLastPathComponent().appendingPathComponent("node_modules/rea-agents").path)
        }
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(support.appendingPathComponent("SwiftCode/Reverse/node_modules/rea-agents").path)
        }
        for candidate in candidates {
            let packageURL = URL(fileURLWithPath: candidate).appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: packageURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String, name == ReverseBridgeProtocol.reaPackageName,
                  let version = json["version"] as? String, version == ReverseBridgeProtocol.pinnedREAVersion
            else { continue }
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    public static func resolveNodeURL() -> URL? {
        let fm = FileManager.default
        func executable(at path: String) -> URL? {
            let expanded = (path as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue,
                  fm.isExecutableFile(atPath: expanded) else { return nil }
            return URL(fileURLWithPath: expanded)
        }
        if let override = nonEmpty(ProcessInfo.processInfo.environment["SWIFTCODE_NODE_PATH"]),
           let url = executable(at: override) {
            return url
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

    public static func nodeMajorVersion(for nodeURL: URL) -> Int? {
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "")
        let major = text.split(separator: ".").first.flatMap { Int($0) }
        return major
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static let secretEnvNameFragments = [
        "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL",
        "PRIVATE_KEY", "API_KEY", "APIKEY", "ACCESS_KEY",
        "AUTH_TOKEN", "CLIENT_SECRET", "SESSION_TOKEN",
    ]

    private static func sanitizedEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { name, _ in
            let upper = name.uppercased()
            return !secretEnvNameFragments.contains { upper.contains($0) }
        }
    }

    private struct RawOutcome {
        let stdout: Data
        let stderr: String
        let exitCode: Int32
        let timedOut: Bool
    }

    private func runMessages(request: ReverseBridgeRequest, timeoutSeconds: TimeInterval) async throws -> ([ReverseBridgeMessage], String) {
        defer {
            lock.withLock {
                _ = cancelledIDs.remove(request.id)
            }
        }
        guard let bridgeURL = Self.resolveBridgeURL() else {
            throw ReverseError.unavailable(
                "Reverse bridge script (ReverseBridge.mjs) was not found.",
                remediation: "Set the bridge path in Settings → Assist → Reverse, or reinstall SwiftCode so the bundled bridge resource is present. Reverse is unavailable until then."
            )
        }
        guard let reaDir = Self.resolveREADirectory(bridgeURL: bridgeURL) else {
            throw ReverseError.unavailable(
                "The pinned REA package (\(ReverseBridgeProtocol.reaPackageName)@\(ReverseBridgeProtocol.pinnedREAVersion)) was not found.",
                remediation: "Set the REA directory in Settings → Assist → Reverse to a folder containing rea-agents@\(ReverseBridgeProtocol.pinnedREAVersion) (package.json version must match). SwiftCode never downloads or installs it automatically."
            )
        }
        guard let nodeURL = Self.resolveNodeURL() else {
            throw ReverseError.unavailable(
                "Node.js was not found.",
                remediation: "Install Node.js 22, 24, or 26 (REA 6.5.0 engines) from nodejs.org or Homebrew, or set SWIFTCODE_NODE_PATH to a Node binary."
            )
        }
        let major = await Task.detached { Self.nodeMajorVersion(for: nodeURL) }.value
        if let major, !ReverseBridgeProtocol.supportedNodeMajors.contains(major) {
            throw ReverseError.unavailable(
                "Node.js v\(major) is not supported by REA \(ReverseBridgeProtocol.pinnedREAVersion).",
                remediation: "Use Node.js 22, 24, or 26."
            )
        }

        let encoder = JSONEncoder()
        let requestData: Data
        do {
            requestData = try encoder.encode(request)
        } catch {
            throw ReverseError(category: .bridgeFailure, code: "reverse_encode_failed", message: "Failed to encode bridge request: \(error.localizedDescription)", retryable: false)
        }

        let raw = try await spawn(
            requestID: request.id,
            nodeURL: nodeURL,
            bridgeURL: bridgeURL,
            reaDir: reaDir,
            requestData: requestData,
            timeoutSeconds: timeoutSeconds
        )

        if raw.timedOut {
            throw ReverseError(category: .timeout, code: "reverse_timeout", message: "Reverse operation timed out after \(Int(timeoutSeconds))s and the bridge process was terminated.", retryable: true, remediation: "Retry with a smaller target, or raise the timeout in Settings → Assist → Reverse.")
        }
        if wasCancelled(request.id) {
            throw ReverseError(category: .cancelled, code: "reverse_cancelled", message: "Reverse operation was cancelled.", retryable: false)
        }

        let text = String(decoding: raw.stdout, as: UTF8.self)
        var messages: [ReverseBridgeMessage] = []
        let decoder = JSONDecoder()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let lineData = Data(line.utf8)
            guard lineData.count <= Self.maxFrameBytes else {
                throw ReverseError(category: .bridgeFailure, code: "reverse_frame_too_large", message: "Bridge frame exceeded the 1 MiB limit.", retryable: false)
            }
            guard let message = try? decoder.decode(ReverseBridgeMessage.self, from: lineData) else {
                throw ReverseError(
                    category: .bridgeFailure, code: "reverse_malformed_frame",
                    message: "Bridge sent a malformed protocol frame.",
                    retryable: false,
                    remediation: "Bridge stderr: \(raw.stderr.prefix(500))"
                )
            }
            guard message.version == ReverseBridgeProtocol.version else {
                throw ReverseError(category: .bridgeFailure, code: "reverse_version_mismatch", message: "Bridge protocol version mismatch (got \(message.version), expected \(ReverseBridgeProtocol.version)).", retryable: false)
            }
            guard message.id == request.id else {
                throw ReverseError(category: .bridgeFailure, code: "reverse_correlation_mismatch", message: "Bridge response correlation ID does not match the request.", retryable: false)
            }
            guard ["progress", "result", "error"].contains(message.type) else {
                throw ReverseError(category: .bridgeFailure, code: "reverse_unknown_frame", message: "Bridge sent an unknown frame type '\(message.type)'.", retryable: false)
            }
            messages.append(message)
        }

        if messages.isEmpty {
            throw ReverseError(
                category: .bridgeFailure, code: "reverse_no_response",
                message: "Bridge exited (code \(raw.exitCode)) without sending a protocol frame.",
                retryable: false,
                remediation: "Bridge stderr: \(raw.stderr.prefix(500))"
            )
        }
        return (messages, raw.stderr)
    }

    private func run(request: ReverseBridgeRequest, timeoutSeconds: TimeInterval) async throws -> ReverseBridgeOutcome {
        let (messages, stderr) = try await runMessages(request: request, timeoutSeconds: timeoutSeconds)
        var progress: [ReverseProgressEvent] = []
        var evidence: ReverseEvidence?
        var bridgeError: ReverseError?
        for message in messages {
            switch message.type {
            case "progress":
                if let event = message.progress { progress.append(event) }
            case "result":
                evidence = message.evidence
            case "error":
                if let payload = message.error { bridgeError = ReverseError.fromBridgePayload(payload) }
            default:
                break
            }
        }
        if let bridgeError {
            return ReverseBridgeOutcome(progress: progress, evidence: bridgeError.partialEvidence, error: bridgeError, stderrTail: stderr)
        }
        guard let evidence else {
            throw ReverseError(category: .bridgeFailure, code: "reverse_missing_evidence", message: "Bridge completed without returning Evidence or an error.", retryable: false, remediation: "Bridge stderr: \(stderr.prefix(500))")
        }
        return ReverseBridgeOutcome(progress: progress, evidence: evidence, error: nil, stderrTail: stderr)
    }

    private func spawn(
        requestID: String,
        nodeURL: URL,
        bridgeURL: URL,
        reaDir: URL,
        requestData: Data,
        timeoutSeconds: TimeInterval
    ) async throws -> RawOutcome {
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [bridgeURL.path, "--rea-dir", reaDir.path]
        process.environment = Self.sanitizedEnvironment()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let box = ProcessBox(process)

        lock.withLock {
            running[requestID] = box
        }
        defer {
            lock.withLock {
                _ = running.removeValue(forKey: requestID)
            }
        }

        do {
            try process.run()
        } catch {
            throw ReverseError(category: .bridgeFailure, code: "reverse_launch_failed", message: "Failed to launch the Reverse bridge: \(error.localizedDescription)", retryable: false)
        }

        let stdoutBox = BoundedDataBox(limit: Self.maxStdoutBytes + 1)
        let stderrBox = BoundedDataBox(limit: Self.maxStderrBytes)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stdoutBox.append(chunk) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stderrBox.append(chunk) }
        }
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: requestData + Data([0x0A]))
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            process.terminate()
            throw ReverseError(category: .bridgeFailure, code: "reverse_write_failed", message: "Failed to write to the Reverse bridge: \(error.localizedDescription)", retryable: false)
        }

        let timedOutBox = FlagBox()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) {
            guard let proc = box.process, proc.isRunning else { return }
            timedOutBox.set(true)
            proc.terminate()
        }

        let exitCode: Int32
        do {
            exitCode = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                    let gate = FlagBox()
                    process.terminationHandler = { finished in
                        finished.terminationHandler = nil
                        if gate.claim() {
                            continuation.resume(returning: finished.terminationStatus)
                        }
                    }
                    if !process.isRunning, gate.claim() {
                        process.terminationHandler = nil
                        continuation.resume(returning: process.terminationStatus)
                    }
                }
            } onCancel: {
                box.process?.terminate()
            }
        } catch is CancellationError {
            throw ReverseError(category: .cancelled, code: "reverse_cancelled", message: "Reverse operation was cancelled.", retryable: false)
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let stdoutTail = stdoutPipe.fileHandleForReading.availableData
        if !stdoutTail.isEmpty { stdoutBox.append(stdoutTail) }
        let stderrTail = stderrPipe.fileHandleForReading.availableData
        if !stderrTail.isEmpty { stderrBox.append(stderrTail) }
        let stdoutData = stdoutBox.data
        if stdoutData.count > Self.maxStdoutBytes {
            throw ReverseError(category: .bridgeFailure, code: "reverse_output_too_large", message: "Bridge stdout exceeded the 8 MiB total limit.", retryable: false)
        }
        let stderrText = String(decoding: stderrBox.data, as: UTF8.self)
        return RawOutcome(stdout: stdoutData, stderr: stderrText, exitCode: exitCode, timedOut: timedOutBox.value)
    }
}

private final class BoundedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var buffer = Data()
    init(limit: Int) { self.limit = limit }
    func append(_ data: Data) {
        lock.withLock {
            buffer.append(data)
            if buffer.count > limit {
                buffer = buffer.suffix(limit)
            }
        }
    }
    var data: Data {
        lock.withLock { buffer }
    }
}

private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set(_ value: Bool) {
        lock.withLock { flag = value }
    }
    var value: Bool {
        lock.withLock { flag }
    }
    func claim() -> Bool {
        lock.withLock {
            guard !flag else { return false }
            flag = true
            return true
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    init(_ process: Process) { _process = process }
    var process: Process? {
        lock.withLock { _process }
    }
}
