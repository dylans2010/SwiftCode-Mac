import Foundation

// MARK: - Extension-host process manager
//
// One Node process per VS Code extension. The process is disposable:
// a crash marks the extension `.crashed` and fails pending requests,
// and after `maxConsecutiveHostCrashes` consecutive crashes the host is
// left stopped until the user explicitly retries — no restart loops.
// All state here is @MainActor-isolated; the reading Task hops back to
// the MainActor for every line it handles.

@MainActor
public final class ExtV2HostManager {
    private struct RunningHost {
        let process: Process
        let stdin: Pipe
        var contribution: ExtV2Contribution
        var crashCount: Int
    }

    public var storage: ExtV2Storage
    public var permissions: ExtV2PermissionManager
    /// Set by the manager: how host-initiated requests (file reads,
    /// diagnostics, provider registration) are served.
    public var hostRequestHandler: ((String, ExtV2RPCRequest) async throws -> ExtV2JSONValue)?

    private var hosts: [String: RunningHost] = [:]
    private var pending: [String: CheckedContinuation<ExtV2JSONValue, Error>] = [:]
    private var nextRequestId = 0
    private var consecutiveCrashes: [String: Int] = [:]

    public init(storage: ExtV2Storage, permissions: ExtV2PermissionManager) {
        self.storage = storage
        self.permissions = permissions
    }

    public func isRunning(extensionId: String) -> Bool {
        hosts[extensionId] != nil
    }

    public func contribution(for extensionId: String) -> ExtV2Contribution? {
        hosts[extensionId]?.contribution
    }

    // MARK: Node discovery

    public func nodeExecutable(settings: ExtV2Storage.Settings) -> URL? {
        if let configured = settings.nodeExecutablePath, !configured.isEmpty,
           FileManager.default.isExecutableFile(atPath: configured) {
            return URL(fileURLWithPath: configured)
        }
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    // MARK: Activation

    /// Activates an installed VS Code extension, returning its real
    /// contributions. Throws when Node is missing, the entry point is
    /// missing, activation times out, or the host reports an error.
    public func activate(
        installed: ExtV2InstalledExtension,
        workspaceRoot: URL?,
        settings: ExtV2Storage.Settings
    ) async throws -> ExtV2Contribution {
        let id = installed.id
        if let existing = hosts[id] { return existing.contribution }
        if (consecutiveCrashes[id] ?? 0) >= ExtV2ResourceLimits.maxConsecutiveHostCrashes {
            throw ExtV2Error.host("Extension host for '\(id)' stopped after repeated crashes. Retry it manually from the extension's details.")
        }
        guard let node = nodeExecutable(settings: settings) else {
            throw ExtV2Error.host("Node.js is required to run VS Code extensions and was not found. Install Node.js or set its path in Extensions > Settings.")
        }
        let packageDir = URL(fileURLWithPath: installed.installPath).appendingPathComponent("extension")
        let manifestURL = packageDir.appendingPathComponent("package.json")
        let manifest = try ExtV2ManifestParser.parseFile(at: manifestURL)
        guard let main = manifest.main else {
            throw ExtV2Error.host("Extension '\(id)' has no main entry point, so there is nothing to activate.")
        }
        let entry = packageDir.appendingPathComponent(main)
        guard FileManager.default.fileExists(atPath: entry.path) else {
            throw ExtV2Error.host("Extension entry point '\(main)' is missing from the installed package.")
        }
        let scriptURL = try ExtV2HostScript.ensureHostScript(storage: storage)
        let process = Process()
        process.executableURL = node
        process.arguments = [scriptURL.path, "--extension-entry", entry.path]
        process.standardError = FileHandle.nullDevice
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        let environment = ProcessInfo.processInfo.environment
        process.environment = environment.filter { key, _ in !key.hasPrefix("SWIFTCODE_") && !key.hasPrefix("HERMES_") }
        do {
            try process.run()
        } catch {
            throw ExtV2Error.host("Could not start the extension host: \(error.localizedDescription)")
        }
        hosts[id] = RunningHost(process: process, stdin: stdinPipe, contribution: .empty, crashCount: 0)
        startReading(extensionId: id, stdout: stdoutPipe)
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                await self?.handleHostExit(extensionId: id)
            }
        }
        do {
            let result = try await request(
                extensionId: id,
                method: "activate",
                params: .object([
                    "extensionId": .string(id),
                    "workspaceRoot": .string(workspaceRoot?.path ?? ""),
                ]),
                timeout: ExtV2ResourceLimits.hostActivationTimeout
            )
            consecutiveCrashes[id] = 0
            guard let contributionObject = result.objectValue?["contribution"],
                  let data = try? JSONEncoder().encode(contributionObject),
                  let contribution = try? JSONDecoder().decode(ExtV2Contribution.self, from: data) else {
                throw ExtV2Error.host("Extension host returned a malformed activation response.")
            }
            hosts[id]?.contribution = contribution
            for language in contributionObject.objectValue?["completionLanguages"]?.arrayValue ?? [] {
                if let lang = language.stringValue {
                    ExtV2ProviderRegistry.shared.registerCompletionProvider(extensionId: id, language: lang)
                }
            }
            ExtV2DiagnosticsService.shared.info("Activated with \(contribution.commands.count) commands.", extensionId: id)
            return contribution
        } catch {
            shutdown(extensionId: id)
            throw error
        }
    }

    public func executeCommand(extensionId: String, command: String, args: [ExtV2JSONValue] = []) async throws -> ExtV2JSONValue {
        guard hosts[extensionId] != nil else {
            throw ExtV2Error.host("Extension '\(extensionId)' is not running.")
        }
        return try await request(
            extensionId: extensionId,
            method: "executeCommand",
            params: .object(["command": .string(command), "args": .array(args)]),
            timeout: ExtV2ResourceLimits.hostCommandTimeout
        )
    }

    /// Finds the running host that owns a command id, if any.
    public func ownerOfCommand(_ command: String) -> String? {
        hosts.first { $0.value.contribution.commands.contains { $0.command == command } }?.key
    }

    public func deactivate(extensionId: String) {
        shutdown(extensionId: extensionId)
        ExtV2ProviderRegistry.shared.clear(for: extensionId)
    }

    public func shutdownAll() {
        for id in Array(hosts.keys) { shutdown(extensionId: id) }
    }

    private func shutdown(extensionId: String) {
        guard let host = hosts[extensionId] else { return }
        hosts.removeValue(forKey: extensionId)
        if host.process.isRunning {
            // Best effort: ask, then terminate. Never wait on the UI thread
            // for a host that has already misbehaved.
            if let data = try? ExtV2RPC.encodeRequest(ExtV2RPCRequest(id: "shutdown", method: "shutdown")) {
                try? host.stdin.fileHandleForWriting.write(contentsOf: data)
            }
            host.process.terminate()
        }
        for (id, continuation) in pending where id.hasPrefix(extensionId + ":") {
            continuation.resume(throwing: ExtV2Error.host("Extension host shut down."))
        }
        pending = pending.filter { !$0.key.hasPrefix(extensionId + ":") }
    }

    // MARK: RPC plumbing

    private func request(
        extensionId: String, method: String, params: ExtV2JSONValue?, timeout: TimeInterval
    ) async throws -> ExtV2JSONValue {
        guard let host = hosts[extensionId] else {
            throw ExtV2Error.host("Extension '\(extensionId)' is not running.")
        }
        nextRequestId += 1
        let requestId = "\(extensionId):\(nextRequestId)"
        let request = ExtV2RPCRequest(id: requestId, method: method, params: params)
        let data = try ExtV2RPC.encodeRequest(request)
        return try await withCheckedThrowingContinuation { continuation in
            pending[requestId] = continuation
            try? host.stdin.fileHandleForWriting.write(contentsOf: data)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.failRequest(id: requestId, error: ExtV2Error.timeout("Extension host did not answer '\(method)' within \(Int(timeout))s."))
            }
        }
    }

    private func failRequest(id: String, error: Error) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
    }

    private func reply(extensionId: String, id: String, result: ExtV2JSONValue?, error: String?) {
        guard let host = hosts[extensionId] else { return }
        let response = ExtV2RPCResponse(
            id: id, result: result,
            error: error.map { ExtV2RPCErrorPayload(code: -32000, message: $0) })
        if let data = try? ExtV2RPC.encodeResponse(response) {
            try? host.stdin.fileHandleForWriting.write(contentsOf: data)
        }
    }

    private func startReading(extensionId: String, stdout: Pipe) {
        Task { [weak self] in
            do {
                for try await line in stdout.fileHandleForReading.bytes.lines {
                    await self?.handleLine(extensionId: extensionId, line: line)
                }
            } catch {
                // A read error ends the stream the same way EOF does:
                // the host is gone, so its exit handling still runs.
            }
            await self?.handleHostExit(extensionId: extensionId)
        }
    }

    private func handleLine(extensionId: String, line: String) async {
        guard let data = line.data(using: .utf8) else { return }
        // A response to one of our requests.
        if let response = try? JSONDecoder().decode(ExtV2RPCResponse.self, from: data),
           let continuation = pending.removeValue(forKey: response.id) {
            if let error = response.error {
                continuation.resume(throwing: ExtV2Error.host(error.message))
            } else {
                continuation.resume(returning: response.result ?? .null)
            }
            return
        }
        // A host-initiated request.
        do {
            let request = try ExtV2RPC.decodeRequest(from: data, fromHost: true)
            do {
                let result = try await hostRequestHandler?(extensionId, request) ?? .null
                reply(extensionId: extensionId, id: request.id, result: result, error: nil)
            } catch {
                reply(extensionId: extensionId, id: request.id, result: nil, error: error.localizedDescription)
            }
        } catch {
            ExtV2DiagnosticsService.shared.error("Rejected IPC line from host: \(error.localizedDescription)", extensionId: extensionId)
        }
    }

    private func handleHostExit(extensionId: String) async {
        guard hosts[extensionId] != nil else { return }
        hosts.removeValue(forKey: extensionId)
        consecutiveCrashes[extensionId, default: 0] += 1
        ExtV2ProviderRegistry.shared.clear(for: extensionId)
        for (id, continuation) in pending where id.hasPrefix(extensionId + ":") {
            continuation.resume(throwing: ExtV2Error.host("Extension host exited unexpectedly."))
        }
        pending = pending.filter { !$0.key.hasPrefix(extensionId + ":") }
        ExtV2DiagnosticsService.shared.error(
            "Extension host exited (consecutive crashes: \(consecutiveCrashes[extensionId] ?? 0)).",
            extensionId: extensionId)
    }
}
