import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import SwiftCodeSubprocess

public enum HostScript {
    public static var source: String {
        guard let url = Bundle.module.url(forResource: "extension-host", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }

    public static func hostScriptURL(storage: ExtensionStorage) -> URL {
        storage.hostDirectory.appendingPathComponent("extension-host.js")
    }

    public static func ensureHostScript(storage: ExtensionStorage) throws -> URL {
        let url = hostScriptURL(storage: storage)
        let source = source
        guard !source.isEmpty else {
            throw SwiftCodeExtensionError.host("The bundled extension host script could not be loaded.")
        }
        try FileManager.default.createDirectory(at: storage.hostDirectory, withIntermediateDirectories: true)
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == source {
            return url
        }
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

final class HostSession: @unchecked Sendable {
    let extensionId: String
    private let process: Process
    private let stdinHandle: FileHandle
    private let lock = NSLock()
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var exited = false
    var onExit: ((Int32) -> Void)?
    var onHostRequest: ((RPCRequest) async throws -> JSONValue)?

    init(extensionId: String, nodeURL: URL, hostScriptURL: URL, entryURL: URL,
         environment: [String: String]) throws {
        self.extensionId = extensionId
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [hostScriptURL.path, "--extension-entry", entryURL.path]
        process.environment = environment
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting
        process.terminationHandler = { [weak self] _ in self?.handleExit(status: process.terminationStatus) }
        do {
            try process.run()
        } catch {
            throw SwiftCodeExtensionError.host("Could not start the extension host for '\(extensionId)': \(error.localizedDescription)")
        }
        let reader = outPipe.fileHandleForReading
        Thread.detachNewThread { [weak self] in self?.readLoop(handle: reader) }
    }

    var isRunning: Bool { process.isRunning }

    func sendRequest(_ request: RPCRequest, timeout: TimeInterval) async throws -> JSONValue {
        let data = try ExtensionRPC.encodeRequest(request)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            lock.lock()
            if exited {
                lock.unlock()
                continuation.resume(throwing: SwiftCodeExtensionError.host("Extension host shut down."))
                return
            }
            pending[request.id] = continuation
            lock.unlock()
            writeQuietly(data, to: stdinHandle)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                let expired = self.lock.withLock { self.pending.removeValue(forKey: request.id) }
                expired?.resume(throwing: SwiftCodeExtensionError.timeout(
                    "Extension host request '\(request.method)' timed out after \(Int(timeout))s."))
            }
        }
    }

    func sendResponse(_ response: RPCResponse) {
        guard let data = try? ExtensionRPC.encodeResponse(response) else { return }
        writeQuietly(data, to: stdinHandle)
    }

    func shutdown() {
        Task {
            let request = RPCRequest(id: "shutdown", method: "shutdown")
            _ = try? await self.sendRequest(request, timeout: 2)
            self.process.terminate()
        }
    }

    func terminate() {
        process.terminate()
    }

    private func handleExit(status: Int32) {
        lock.lock()
        guard !exited else { lock.unlock(); return }
        exited = true
        let pending = self.pending
        self.pending.removeAll()
        lock.unlock()
        for (_, continuation) in pending {
            continuation.resume(throwing: SwiftCodeExtensionError.host("Extension host exited unexpectedly."))
        }
        try? stdinHandle.close()
        onExit?(status)
    }

    private func readLoop(handle: FileHandle) {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                handleLine(line)
            }
        }
        handleExit(status: process.terminationStatus)
    }

    private func handleLine(_ line: Data) {
        guard !line.isEmpty else { return }
        guard line.count <= ResourceLimits.maxIPCMessageBytes else {
            DiagnosticsService.shared.error("IPC line exceeded the 1 MiB limit.", extensionId: extensionId)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let id = object["id"] as? String,
           object["result"] != nil || object["error"] != nil {
            lock.lock()
            let continuation = pending.removeValue(forKey: id)
            lock.unlock()
            guard let continuation else { return }
            if let errorObject = object["error"] as? [String: Any] {
                let message = errorObject["message"] as? String ?? "Host request failed."
                if id == "fatal" {
                    continuation.resume(throwing: SwiftCodeExtensionError.host("Host crashed: \(message)"))
                } else {
                    continuation.resume(throwing: SwiftCodeExtensionError.host(message))
                }
            } else {
                let result = jsonValue(from: object["result"] ?? NSNull())
                continuation.resume(returning: result)
            }
            return
        }
        guard let request = try? ExtensionRPC.decodeRequest(from: line, fromHost: true) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let handler = self.onHostRequest else {
                    self.sendResponse(RPCResponse(id: request.id, result: .null))
                    return
                }
                let result = try await handler(request)
                self.sendResponse(RPCResponse(id: request.id, result: result))
            } catch {
                self.sendResponse(RPCResponse(id: request.id, error: RPCErrorPayload(code: -32000, message: error.localizedDescription)))
            }
        }
    }

    private func jsonValue(from value: Any) -> JSONValue {
        switch value {
        case is NSNull: return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0,
               let int = Int(exactly: number.int64Value) { return .int(int) }
            return .double(number.doubleValue)
        case let string as String: return .string(string)
        case let array as [Any]: return .array(array.map { jsonValue(from: $0) })
        case let dict as [String: Any]: return .object(dict.mapValues { jsonValue(from: $0) })
        default: return .string(String(describing: value))
        }
    }

    private func writeQuietly(_ data: Data, to handle: FileHandle) {
        let fd = handle.fileDescriptor
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard var pointer = raw.baseAddress else { return }
            var left = raw.count
            while left > 0 {
                #if canImport(Glibc)
                let written = Glibc.write(fd, pointer, left)
                #else
                let written = Darwin.write(fd, pointer, left)
                #endif
                if written < 0 {
                    if errno == EINTR { continue }
                    return
                }
                left -= written
                pointer += written
            }
        }
    }
}

@MainActor
public final class ExtensionHostManager {
    public var storage: ExtensionStorage
    public var permissions: PermissionManager
    public var hostRequestHandler: ((String, RPCRequest) async throws -> JSONValue)?

    private var sessions: [String: HostSession] = [:]
    private var contributions: [String: ExtensionContribution] = [:]
    private var commandOwners: [String: String] = [:]
    private var requestCounter = 0
    private(set) var consecutiveCrashes: [String: Int] = [:]

    public init(storage: ExtensionStorage, permissions: PermissionManager) {
        self.storage = storage
        self.permissions = permissions
    }

    public func nodeExecutable(settings: ExtensionSettings) -> URL? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["SWIFTCODE_NODE_PATH"],
           !override.isEmpty, fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        if let configured = settings.nodeExecutablePath, !configured.isEmpty,
           fileManager.isExecutableFile(atPath: configured) {
            return URL(fileURLWithPath: configured)
        }
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] {
            if fileManager.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = "\(directory)/node"
                if fileManager.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
            }
        }
        return nil
    }

    private func nextRequestID(for extensionId: String) -> String {
        requestCounter += 1
        return "\(extensionId):\(requestCounter)"
    }

    public func isRunning(extensionId: String) -> Bool {
        sessions[extensionId]?.isRunning ?? false
    }

    public func contribution(for extensionId: String) -> ExtensionContribution? {
        contributions[extensionId]
    }

    public func ownerOfCommand(_ command: String) -> String? {
        commandOwners[command]
    }

    private(set) var quarantined: [String: String] = [:]

    public func isQuarantined(_ extensionId: String) -> Bool {
        quarantined[extensionId] != nil
    }

    public func quarantineReason(for extensionId: String) -> String? {
        quarantined[extensionId]
    }

    public func clearQuarantine(for extensionId: String) {
        guard quarantined.removeValue(forKey: extensionId) != nil else { return }
        consecutiveCrashes.removeValue(forKey: extensionId)
    }

    public func activate(installed: InstalledExtension, workspaceRoot: URL?,
                         settings: ExtensionSettings) async throws -> ExtensionContribution {
        let id = installed.id
        if let existing = contributions[id], isRunning(extensionId: id) {
            return existing
        }
        if let reason = quarantined[id] {
            throw SwiftCodeExtensionError.host("Extension '\(id)' is quarantined: \(reason) Re-enable it to try again.")
        }
        if (consecutiveCrashes[id] ?? 0) >= ResourceLimits.maxConsecutiveHostCrashes {
            throw SwiftCodeExtensionError.host(
                "Extension host for '\(id)' stopped after repeated crashes. Retry it manually from the extension's details.")
        }
        guard let nodeURL = nodeExecutable(settings: settings) else {
            throw SwiftCodeExtensionError.host(
                "Node.js is required to run VS Code extensions and was not found. Install Node.js 20 or later or set its path in Extensions > Settings.")
        }
        try await requireNode20(nodeURL: nodeURL)
        let manifestURL = URL(fileURLWithPath: installed.installPath)
            .appendingPathComponent("extension/package.json")
        let manifest = try VSCodeManifestParser.parseFile(at: manifestURL)
        guard let main = manifest.main else {
            throw SwiftCodeExtensionError.host("Extension '\(id)' has no main entry point.")
        }
        let entryURL = URL(fileURLWithPath: installed.installPath)
            .appendingPathComponent("extension").appendingPathComponent(main)
        let scriptURL = try HostScript.ensureHostScript(storage: storage)
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("SWIFTCODE_") || key.hasPrefix("HERMES_") {
            environment.removeValue(forKey: key)
        }
        let session = try HostSession(extensionId: id, nodeURL: nodeURL, hostScriptURL: scriptURL,
                                      entryURL: entryURL, environment: environment)
        let hostHandler = self.hostRequestHandler
        session.onHostRequest = { request in
            guard let hostHandler else { return .null }
            return try await hostHandler(id, request)
        }
        session.onExit = { [weak self] status in
            Task {
                await MainActor.run { [weak self] in
                    self?.noteHostExit(extensionId: id, status: status)
                }
            }
        }
        sessions[id] = session
        do {
            let params: JSONValue = .object([
                "extensionId": .string(id),
                "workspaceRoot": .string(workspaceRoot?.path ?? ""),
            ])
            let request = RPCRequest(id: nextRequestID(for: id), method: "activate", params: params)
            let result = try await session.sendRequest(request, timeout: ResourceLimits.hostActivationTimeout)
            let contribution = Self.contribution(from: result)
            contributions[id] = contribution
            for command in contribution.commands { commandOwners[command.command] = id }
            consecutiveCrashes[id] = 0
            return contribution
        } catch {
            sessions.removeValue(forKey: id)
            session.terminate()
            throw error
        }
    }

    public func executeCommand(extensionId: String, command: String,
                               args: [JSONValue] = []) async throws -> JSONValue {
        guard let session = sessions[extensionId], session.isRunning else {
            throw SwiftCodeExtensionError.host("Extension host for '\(extensionId)' is not running.")
        }
        let params: JSONValue = .object(["command": .string(command), "args": .array(args)])
        let request = RPCRequest(id: nextRequestID(for: extensionId), method: "executeCommand", params: params)
        return try await session.sendRequest(request, timeout: ResourceLimits.hostCommandTimeout)
    }

    public func deactivate(extensionId: String) {
        guard let session = sessions.removeValue(forKey: extensionId) else { return }
        contributions.removeValue(forKey: extensionId)
        commandOwners = commandOwners.filter { $0.value != extensionId }
        session.shutdown()
    }

    public func shutdownAll() {
        for id in Array(sessions.keys) { deactivate(extensionId: id) }
    }

    public func resetCrashCounter(for extensionId: String) {
        consecutiveCrashes[extensionId] = 0
    }

    private func noteHostExit(extensionId: String, status: Int32) {
        sessions.removeValue(forKey: extensionId)
        contributions.removeValue(forKey: extensionId)
        commandOwners = commandOwners.filter { $0.value != extensionId }
        ProviderRegistry.shared.clear(for: extensionId)
        consecutiveCrashes[extensionId, default: 0] += 1
        DiagnosticsService.shared.error(
            "Extension host for '\(extensionId)' exited unexpectedly (status \(status)).",
            extensionId: extensionId)
        if (consecutiveCrashes[extensionId] ?? 0) >= ResourceLimits.maxConsecutiveHostCrashes {
            quarantine(extensionId: extensionId, reason: "It crashed \(consecutiveCrashes[extensionId] ?? 0) times in a row and was quarantined to protect stability. Last exit code: \(status).")
        }
    }

    private func quarantine(extensionId: String, reason: String) {
        quarantined[extensionId] = reason
        DiagnosticsService.shared.error("Extension '\(extensionId)' was quarantined: \(reason)", extensionId: extensionId)
    }

    private func requireNode20(nodeURL: URL) async throws {
        let output = await Task.detached {
            try? Subprocess.run(nodeURL.path, ["--version"])
        }.value
        guard let output else {
            throw SwiftCodeExtensionError.host("Could not run Node.js to check its version.")
        }
        let versionText = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        let numeric = versionText.hasPrefix("v") ? String(versionText.dropFirst()) : versionText
        let major = numeric.split(separator: ".").first.flatMap { Int($0) } ?? 0
        guard major >= 20 else {
            throw SwiftCodeExtensionError.host(
                "Node.js 20 or later is required to run VS Code extensions; found \(versionText).")
        }
    }

    static func contribution(from result: JSONValue) -> ExtensionContribution {
        guard let object = result.objectValue else { return .empty }
        func commands(_ value: JSONValue?) -> [ExtensionContributionCommand] {
            (value?.arrayValue ?? []).compactMap { item in
                guard let dict = item.objectValue,
                      let command = dict["command"]?.stringValue,
                      let title = dict["title"]?.stringValue else { return nil }
                return ExtensionContributionCommand(command: command, title: title)
            }
        }
        func views(_ value: JSONValue?) -> [ExtensionContributionView] {
            (value?.arrayValue ?? []).compactMap { item in
                guard let dict = item.objectValue,
                      let id = dict["id"]?.stringValue,
                      let name = dict["name"]?.stringValue else { return nil }
                return ExtensionContributionView(id: id, name: name)
            }
        }
        func treeItems(_ value: JSONValue?) -> [ExtensionTreeItem] {
            (value?.arrayValue ?? []).compactMap { item in
                guard let dict = item.objectValue,
                      let id = dict["id"]?.stringValue,
                      let label = dict["label"]?.stringValue else { return nil }
                return ExtensionTreeItem(id: id, label: label,
                                         description: dict["description"]?.stringValue,
                                         command: dict["command"]?.stringValue)
            }
        }
        let outputLines = (object["outputLines"]?.arrayValue ?? []).compactMap { $0.stringValue }
        return ExtensionContribution(
            commands: commands(object["commands"]),
            views: views(object["views"]),
            treeItems: treeItems(object["treeItems"]),
            statusBarText: object["statusBarText"]?.stringValue,
            outputLines: outputLines,
            webviewHTML: object["webviewHTML"]?.stringValue)
    }
}
