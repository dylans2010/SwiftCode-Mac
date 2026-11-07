import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "SDKRuntimeManager")

public enum SDKProvider: String, CaseIterable, Sendable {
    case openCode = "opencode"
    case openRouter = "openrouter"

    public var displayName: String {
        switch self {
        case .openCode: return "OpenCode"
        case .openRouter: return "OpenRouter"
        }
    }

    public var packageName: String {
        switch self {
        case .openCode: return "@opencode-ai/sdk"
        case .openRouter: return "@openrouter/agent"
        }
    }

    public var pinnedVersion: String {
        switch self {
        case .openCode: return "1.19.5"
        case .openRouter: return "0.11.0"
        }
    }

    public var pinnedRequirement: String { "\(packageName)@\(pinnedVersion)" }
}

public enum SDKToolSourceSetting: String, CaseIterable, Sendable {
    case swiftcode
    case openrouter
    case opencode
    case combined

    public var displayName: String {
        switch self {
        case .swiftcode: return "SwiftCode tools"
        case .openrouter: return "OpenRouter tools"
        case .opencode: return "OpenCode tools"
        case .combined: return "Combined tools"
        }
    }

    public var explanation: String {
        switch self {
        case .swiftcode:
            return "Only SwiftCode Assist tools. Every call is validated, permission-checked, and executed by SwiftCode's dispatcher."
        case .openrouter:
            return "Only host tools executed through the OpenRouter Agent SDK (fetch_url and current_datetime). These are SwiftCode-authored JS host tools, not OpenRouter's own server tools; SwiftCode does not execute them, it observes their events."
        case .opencode:
            return "Only tools from the OpenCode runtime. SwiftCode does not execute these; it observes their events."
        case .combined:
            return "SwiftCode tools plus the selected provider's own tools. Provider tools run under the provider runtime's permissions, not SwiftCode's — use only when that is acceptable for the workspace."
        }
    }

    private static let defaultsKey = "assist.toolSource"

    @MainActor
    public static func effective() -> SDKToolSourceSetting {
        let toolkit = AppSettings.shared.assistToolkit
        if toolkit.caseInsensitiveCompare("system") == .orderedSame {
            return .swiftcode
        }
        if AppSettings.shared.isProviderToolkit {
            if AppSettings.shared.isOpenRouterAssist { return .openrouter }
            if AppSettings.shared.isOpenCodeAssist { return .opencode }
        }
        return load()
    }

    public static func load() -> SDKToolSourceSetting {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let source = SDKToolSourceSetting(rawValue: raw) else {
            return .swiftcode
        }
        return source
    }

    public func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

public enum SDKRuntimeKind: String, Sendable {
    case node
    case bun
}

public struct SDKRuntimeStatus: Equatable, Sendable {
    public let provider: SDKProvider
    public let runtimeKind: SDKRuntimeKind?
    public let runtimePath: String?
    public let installedVersion: String?
    public let expectedVersion: String
    public let ownedProcessIdentifier: Int32?
    public let lastBridgeExitCode: Int32?

    public var isRuntimeAvailable: Bool { runtimeKind != nil }
    public var isInstalled: Bool { installedVersion == expectedVersion }
    public var isBridgeRunning: Bool { ownedProcessIdentifier != nil }

    public var summary: String {
        if let kind = runtimeKind, let installed = installedVersion, installed == expectedVersion {
            return "\(kind.rawValue) · \(provider.packageName) \(installed) installed"
        }
        if runtimeKind == nil {
            return "No JavaScript runtime found — install Node.js LTS (preferred) or Bun, then Install."
        }
        if let installed = installedVersion {
            return "Installed \(installed) does not match pinned \(expectedVersion) — use Repair."
        }
        return "SDK not installed — use Install."
    }
}

public enum SDKRuntimeError: Error, LocalizedError, Sendable {
    case runtimeMissing
    case packageManagerMissing(SDKRuntimeKind)
    case notInstalled(SDKProvider)
    case corruptInstall(SDKProvider, found: String?)
    case installFailed(SDKProvider, detail: String)
    case installTimeout(SDKProvider)
    case installCancelled(SDKProvider)
    case bridgeScriptMissing(URL)
    case bridgeScriptNotUnderRuntimeDirectory(URL)
    case startupTimeout(SDKProvider)
    case startupFailed(SDKProvider, detail: String)
    case bridgeCrashed(SDKProvider, exitCode: Int32, detail: String)
    case bridgeNotRunning(SDKProvider)
    case missingOpenRouterKey
    case processLaunchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            return "No JavaScript runtime found. Install Node.js LTS from nodejs.org (preferred) or Bun from bun.sh, make sure it is on PATH, then try again."
        case .packageManagerMissing(let kind):
            return "Found \(kind.rawValue) but not its package manager. Reinstall \(kind.rawValue) so npm (for Node) or bun install (for Bun) is available on PATH."
        case .notInstalled(let provider):
            return "\(provider.displayName) SDK is not installed. Use Install in Assist Settings."
        case .corruptInstall(let provider, let found):
            return "\(provider.displayName) SDK install is incomplete or damaged (found: \(found ?? "nothing")). Use Repair in Assist Settings."
        case .installFailed(let provider, let detail):
            return "\(provider.displayName) SDK install failed: \(detail)"
        case .installTimeout(let provider):
            return "\(provider.displayName) SDK install timed out. Check the network connection and try Repair."
        case .installCancelled(let provider):
            return "\(provider.displayName) SDK install was cancelled."
        case .bridgeScriptMissing(let url):
            return "Bridge script missing at \(url.path). The provider workstream must place it with writeBridgeScript before launch."
        case .bridgeScriptNotUnderRuntimeDirectory(let url):
            return "Bridge script \(url.path) is not under the SDK runtime directory, so ESM package imports would not resolve. Place it with writeBridgeScript."
        case .startupTimeout(let provider):
            return "\(provider.displayName) bridge did not report ready within the timeout. Check that the SDK runtime is installed and the provider is reachable, then try again."
        case .startupFailed(let provider, let detail):
            return "\(provider.displayName) bridge failed to start: \(detail)"
        case .bridgeCrashed(let provider, let exitCode, let detail):
            return "\(provider.displayName) bridge exited unexpectedly (code \(exitCode)): \(detail)"
        case .bridgeNotRunning(let provider):
            return "\(provider.displayName) bridge is not running."
        case .missingOpenRouterKey:
            return "No OpenRouter API key is saved. Save one in the API Keys section of Assist Settings first — the key itself is never shown here."
        case .processLaunchFailed(let detail):
            return "Could not launch a process: \(detail)"
        }
    }
}

public actor SDKRuntimeManager {
    public static let shared = SDKRuntimeManager()

    public static let installTimeout: TimeInterval = 300
    public static let readyTimeout: TimeInterval = 30
    public static let terminationGrace: TimeInterval = 2

    private struct BridgeState {
        var process: Process
        var stdin: FileHandle
        var stdoutTask: Task<Void, Never>?
        var stderrTask: Task<Void, Never>?
        var stdoutContinuation: AsyncStream<String>.Continuation?
        var lines: [String] = []
        var stderrTail: [String] = []
        var terminationHandlers: [UUID: @Sendable (Int32) -> Void] = [:]
        var shutdownRequested = false
    }

    private var installTasks: [SDKProvider: Task<SDKRuntimeStatus, Error>] = [:]
    private var bridges: [SDKProvider: BridgeState] = [:]
    private var installLogs: [SDKProvider: [String]] = [:]

    public init() {}

    public static func runtimeRoot() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SwiftCode", isDirectory: true)
            .appendingPathComponent("SDKRuntime", isDirectory: true)
    }

    public static func runtimeDirectory(for provider: SDKProvider) -> URL? {
        runtimeRoot()?.appendingPathComponent(provider.rawValue, isDirectory: true)
    }

    public static func bridgeDirectory(for provider: SDKProvider) -> URL? {
        runtimeDirectory(for: provider)?.appendingPathComponent("bridge", isDirectory: true)
    }

    public static func detectRuntime() -> (kind: SDKRuntimeKind, path: String)? {
        let fm = FileManager.default
        var searchDirs: [String] = []
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            searchDirs.append(contentsOf: pathEnv.split(separator: ":").map(String.init))
        }
        searchDirs.append(contentsOf: [
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin",
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".bun/bin").path,
        ])
        for dir in searchDirs where !dir.isEmpty {
            let nodePath = (dir as NSString).appendingPathComponent("node")
            if fm.isExecutableFile(atPath: nodePath) { return (.node, nodePath) }
        }
        for dir in searchDirs where !dir.isEmpty {
            let bunPath = (dir as NSString).appendingPathComponent("bun")
            if fm.isExecutableFile(atPath: bunPath) { return (.bun, bunPath) }
        }
        return nil
    }

    private static func resolvePackageManager(for kind: SDKRuntimeKind, runtimePath: String) -> String? {
        let fm = FileManager.default
        let binDir = (runtimePath as NSString).deletingLastPathComponent
        switch kind {
        case .node:
            let npm = (binDir as NSString).appendingPathComponent("npm")
            if fm.isExecutableFile(atPath: npm) { return npm }
            if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
                for dir in pathEnv.split(separator: ":").map(String.init) {
                    let candidate = (dir as NSString).appendingPathComponent("npm")
                    if fm.isExecutableFile(atPath: candidate) { return candidate }
                }
            }
            return nil
        case .bun:
            return runtimePath
        }
    }

    private static func minimalEnvironment(runtimePath: String) -> [String: String] {
        let binDir = (runtimePath as NSString).deletingLastPathComponent
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var env: [String: String] = [:]
        env["PATH"] = "\(binDir):/usr/bin:/bin" + (existingPath.isEmpty ? "" : ":\(existingPath)")
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["TMPDIR"] = FileManager.default.temporaryDirectory.path
        return env
    }

    public static func installedVersion(for provider: SDKProvider) -> String? {
        guard let dir = runtimeDirectory(for: provider) else { return nil }
        let packageJSON = dir
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent(provider.packageName, isDirectory: true)
            .appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageJSON),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String, !version.isEmpty else {
            return nil
        }
        return version
    }

    public func status(for provider: SDKProvider) -> SDKRuntimeStatus {
        let detected = Self.detectRuntime()
        let installed = Self.installedVersion(for: provider)
        let bridge = bridges[provider]
        return SDKRuntimeStatus(
            provider: provider,
            runtimeKind: detected?.kind,
            runtimePath: detected?.path,
            installedVersion: installed,
            expectedVersion: provider.pinnedVersion,
            ownedProcessIdentifier: bridge.map { $0.process.processIdentifier },
            lastBridgeExitCode: lastBridgeExits[provider]
        )
    }

    public func statuses() -> [SDKProvider: SDKRuntimeStatus] {
        var out: [SDKProvider: SDKRuntimeStatus] = [:]
        for provider in SDKProvider.allCases { out[provider] = status(for: provider) }
        return out
    }

    public func installLog(for provider: SDKProvider) -> [String] {
        installLogs[provider] ?? []
    }

    public func ensureInstalled(
        for provider: SDKProvider,
        force: Bool = false,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> SDKRuntimeStatus {
        if let existing = installTasks[provider] {
            return try await existing.value
        }
        let task = Task { try await self.performInstall(for: provider, force: force, progress: progress) }
        installTasks[provider] = task
        do {
            let result = try await task.value
            installTasks[provider] = nil
            return result
        } catch {
            installTasks[provider] = nil
            throw error
        }
    }

    private func performInstall(
        for provider: SDKProvider,
        force: Bool,
        progress: (@Sendable (String) -> Void)?
    ) async throws -> SDKRuntimeStatus {
        guard let detected = Self.detectRuntime() else {
            throw SDKRuntimeError.runtimeMissing
        }
        guard let managerPath = Self.resolvePackageManager(for: detected.kind, runtimePath: detected.path) else {
            throw SDKRuntimeError.packageManagerMissing(detected.kind)
        }
        guard let dir = Self.runtimeDirectory(for: provider) else {
            throw SDKRuntimeError.installFailed(provider, detail: "Could not resolve the Application Support directory.")
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw SDKRuntimeError.installFailed(provider, detail: "Could not create \(dir.path): \(error.localizedDescription)")
        }

        let currentlyInstalled = Self.installedVersion(for: provider)
        if force || (currentlyInstalled != nil && currentlyInstalled != provider.pinnedVersion) {
            try? fm.removeItem(at: dir.appendingPathComponent("node_modules", isDirectory: true))
            progress?("Removed stale node_modules; reinstalling \(provider.pinnedRequirement).")
        } else if currentlyInstalled == provider.pinnedVersion {
            progress?("\(provider.pinnedRequirement) already installed and verified.")
            return status(for: provider)
        }

        let manifest: [String: Any] = [
            "name": "swiftcode-sdk-runtime-\(provider.rawValue)",
            "private": true,
            "type": "module",
            "dependencies": [provider.packageName: provider.pinnedVersion],
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dir.appendingPathComponent("package.json"), options: .atomic)
        } catch {
            throw SDKRuntimeError.installFailed(provider, detail: "Could not write package.json: \(error.localizedDescription)")
        }

        var arguments: [String]
        switch detected.kind {
        case .node:
            arguments = ["install", "--no-audit", "--no-fund"]
        case .bun:
            arguments = ["install"]
        }
        progress?("Running \(detected.kind.rawValue) install for \(provider.pinnedRequirement)…")

        let exitCode: Int32
        do {
            exitCode = try await runCapturingProcess(
                executable: managerPath,
                arguments: arguments,
                workingDirectory: dir,
                environment: Self.installEnvironment(runtimePath: detected.path, runtimeDir: dir),
                timeout: Self.installTimeout,
                logKey: provider,
                progress: progress
            )
        } catch let error as SDKRuntimeError {
            try? fm.removeItem(at: dir.appendingPathComponent("node_modules", isDirectory: true))
            if case .installTimeout = error { throw SDKRuntimeError.installTimeout(provider) }
            throw error
        } catch {
            try? fm.removeItem(at: dir.appendingPathComponent("node_modules", isDirectory: true))
            throw SDKRuntimeError.installFailed(provider, detail: error.localizedDescription)
        }
        guard exitCode == 0 else {
            try? fm.removeItem(at: dir.appendingPathComponent("node_modules", isDirectory: true))
            let tail = installLogs[provider]?.suffix(5).joined(separator: "\n") ?? ""
            throw SDKRuntimeError.installFailed(provider, detail: "Installer exited with code \(exitCode). \(tail)")
        }

        guard let verified = Self.installedVersion(for: provider), verified == provider.pinnedVersion else {
            try? fm.removeItem(at: dir.appendingPathComponent("node_modules", isDirectory: true))
            throw SDKRuntimeError.corruptInstall(provider, found: Self.installedVersion(for: provider))
        }
        progress?("Installed and verified \(provider.pinnedRequirement).")
        logger.info("SDK runtime installed: \(provider.pinnedRequirement, privacy: .public)")
        return status(for: provider)
    }

    private static func installEnvironment(runtimePath: String, runtimeDir: URL) -> [String: String] {
        var env = minimalEnvironment(runtimePath: runtimePath)
        env["NPM_CONFIG_CACHE"] = runtimeDir.appendingPathComponent(".npm-cache", isDirectory: true).path
        return env
    }

    @discardableResult
    public func writeBridgeScript(for provider: SDKProvider, fileName: String, contents: String) throws -> URL {
        guard fileName.hasSuffix(".mjs"),
              !fileName.contains("/"), !fileName.contains("\\"), fileName != "..", !fileName.hasPrefix(".") else {
            throw SDKRuntimeError.bridgeScriptNotUnderRuntimeDirectory(URL(fileURLWithPath: fileName))
        }
        guard let bridgeDir = Self.bridgeDirectory(for: provider) else {
            throw SDKRuntimeError.processLaunchFailed("Could not resolve the Application Support directory.")
        }
        do {
            try FileManager.default.createDirectory(at: bridgeDir, withIntermediateDirectories: true)
            let url = bridgeDir.appendingPathComponent(fileName)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            return url
        } catch {
            throw SDKRuntimeError.processLaunchFailed("Could not write bridge script: \(error.localizedDescription)")
        }
    }

    public struct BridgeInfo: Sendable {
        public let provider: SDKProvider
        public let processIdentifier: Int32
        public let sdkVersion: String
    }

    public func launchBridge(
        provider: SDKProvider,
        scriptURL: URL,
        extraEnvironment: [String: String] = [:],
        readyTimeout: TimeInterval = SDKRuntimeManager.readyTimeout
    ) async throws -> BridgeInfo {
        guard let detected = Self.detectRuntime() else {
            throw SDKRuntimeError.runtimeMissing
        }
        guard let dir = Self.runtimeDirectory(for: provider) else {
            throw SDKRuntimeError.startupFailed(provider, detail: "Could not resolve the Application Support directory.")
        }
        guard Self.installedVersion(for: provider) == provider.pinnedVersion else {
            throw SDKRuntimeError.corruptInstall(provider, found: Self.installedVersion(for: provider))
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptURL.path) else {
            throw SDKRuntimeError.bridgeScriptMissing(scriptURL)
        }
        guard let bridgeDir = Self.bridgeDirectory(for: provider),
              scriptURL.path.hasPrefix(bridgeDir.path) else {
            throw SDKRuntimeError.bridgeScriptNotUnderRuntimeDirectory(scriptURL)
        }

        if bridges[provider] != nil {
            await terminateBridge(provider: provider)
        }

        var environment = Self.minimalEnvironment(runtimePath: detected.path)
        environment["NODE_PATH"] = dir.appendingPathComponent("node_modules", isDirectory: true).path
        for (key, value) in extraEnvironment { environment[key] = value }
        if provider == .openRouter {
            let key = await MainActor.run { OpenRouterClient.resolveOpenRouterAPIKey() }
            guard !key.isEmpty else { throw SDKRuntimeError.missingOpenRouterKey }
            environment["OPENROUTER_API_KEY"] = key
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: detected.path)
        process.arguments = [scriptURL.path]
        process.environment = environment
        process.currentDirectoryURL = dir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        let state = BridgeState(process: process, stdin: stdinPipe.fileHandleForWriting)
        bridges[provider] = state

        let stdoutTask = Task { [weak self] in
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    await self?.appendBridgeLine(provider: provider, line: line)
                }
            } catch {  }
        }
        let stderrTask = Task { [weak self] in
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    await self?.appendBridgeStderr(provider: provider, line: line)
                }
            } catch {  }
        }
        bridges[provider]?.stdoutTask = stdoutTask
        bridges[provider]?.stderrTask = stderrTask

        process.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleBridgeTermination(provider: provider, exitCode: proc.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            bridges[provider] = nil
            stdoutTask.cancel(); stderrTask.cancel()
            throw SDKRuntimeError.processLaunchFailed(error.localizedDescription)
        }
        logger.info("Launched \(provider.displayName, privacy: .public) bridge (PID: \(process.processIdentifier))")

        let deadline = Date().addingTimeInterval(readyTimeout)
        var readyVersion: String?
        while Date() < deadline {
            if let line = bridges[provider]?.lines.first(where: { Self.parseReadyLine($0) != nil }),
               let parsed = Self.parseReadyLine(line) {
                if parsed.provider != provider.rawValue {
                    await terminateBridge(provider: provider)
                    throw SDKRuntimeError.startupFailed(provider, detail: "Bridge reported provider '\(parsed.provider)', expected '\(provider.rawValue)'.")
                }
                if parsed.sdkVersion != provider.pinnedVersion {
                    await terminateBridge(provider: provider)
                    throw SDKRuntimeError.startupFailed(provider, detail: "Bridge reported SDK version '\(parsed.sdkVersion)', expected pinned '\(provider.pinnedVersion)'.")
                }
                readyVersion = parsed.sdkVersion
                break
            }
            if let proc = bridges[provider]?.process, !proc.isRunning {
                let detail = bridges[provider]?.stderrTail.suffix(5).joined(separator: "\n") ?? ""
                await terminateBridge(provider: provider)
                throw SDKRuntimeError.startupFailed(provider, detail: detail.isEmpty ? "Bridge exited before reporting ready." : detail)
            }
            if Task.isCancelled {
                await terminateBridge(provider: provider)
                throw CancellationError()
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let sdkVersion = readyVersion else {
            await terminateBridge(provider: provider)
            throw SDKRuntimeError.startupTimeout(provider)
        }
        return BridgeInfo(provider: provider, processIdentifier: process.processIdentifier, sdkVersion: sdkVersion)
    }

    private static func parseReadyLine(_ line: String) -> (provider: String, sdkVersion: String)? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "ready",
              let provider = json["provider"] as? String, !provider.isEmpty,
              let sdkVersion = json["sdkVersion"] as? String, !sdkVersion.isEmpty else {
            return nil
        }
        return (provider, sdkVersion)
    }

    private func appendBridgeLine(provider: SDKProvider, line: String) {
        guard var state = bridges[provider] else { return }
        state.lines.append(line)
        if state.lines.count > 500 { state.lines.removeFirst(state.lines.count - 500) }
        bridges[provider] = state
        bridges[provider]?.stdoutContinuation?.yield(line)
    }

    private func appendBridgeStderr(provider: SDKProvider, line: String) {
        guard var state = bridges[provider] else { return }
        state.stderrTail.append(line)
        if state.stderrTail.count > 200 { state.stderrTail.removeFirst(state.stderrTail.count - 200) }
        bridges[provider] = state
        logger.debug("Bridge stderr [\(provider.rawValue, privacy: .public)]: \(line, privacy: .public)")
    }

    private func handleBridgeTermination(provider: SDKProvider, exitCode: Int32) {
        guard let state = bridges[provider] else { return }
        state.stdoutTask?.cancel()
        state.stderrTask?.cancel()
        state.stdoutContinuation?.finish()
        let handlers = state.terminationHandlers
        let wasShutdown = state.shutdownRequested
        let stderrTail = state.stderrTail
        bridges[provider] = nil
        lastBridgeExits[provider] = exitCode
        lastBridgeStderrTails[provider] = stderrTail
        for (_, handler) in handlers { handler(exitCode) }
        if !wasShutdown {
            let tail = stderrTail.suffix(3).joined(separator: " | ")
            logger.error("Bridge crashed [\(provider.rawValue, privacy: .public)] exit \(exitCode): \(tail, privacy: .public)")
        }
    }

    private var lastBridgeExits: [SDKProvider: Int32] = [:]
    private var lastBridgeStderrTails: [SDKProvider: [String]] = [:]

    public func takeBridgeOutputStream(for provider: SDKProvider) -> AsyncStream<String>? {
        guard var state = bridges[provider], state.stdoutContinuation == nil else { return nil }
        let (stream, continuation) = AsyncStream<String>.makeStream()
        for line in state.lines where Self.parseReadyLine(line) == nil {
            continuation.yield(line)
        }
        state.stdoutContinuation = continuation
        bridges[provider] = state
        return stream
    }

    public func sendBridgeLine(provider: SDKProvider, line: String) throws {
        guard let state = bridges[provider], state.process.isRunning else {
            throw SDKRuntimeError.bridgeNotRunning(provider)
        }
        var text = line
        if !text.hasSuffix("\n") { text += "\n" }
        guard let data = text.data(using: .utf8) else {
            throw SDKRuntimeError.processLaunchFailed("Could not encode bridge input.")
        }
        state.stdin.write(data)
    }

    public func onBridgeTermination(provider: SDKProvider, handler: @escaping @Sendable (Int32) -> Void) -> UUID? {
        guard var state = bridges[provider] else { return nil }
        let id = UUID()
        state.terminationHandlers[id] = handler
        bridges[provider] = state
        return id
    }

    public func removeBridgeTerminationHandler(provider: SDKProvider, id: UUID) {
        bridges[provider]?.terminationHandlers.removeValue(forKey: id)
    }

    public func lastBridgeExitCode(for provider: SDKProvider) -> Int32? {
        lastBridgeExits[provider]
    }

    public func bridgeStderrTail(for provider: SDKProvider) -> [String] {
        bridges[provider]?.stderrTail ?? lastBridgeStderrTails[provider] ?? []
    }

    public func terminateBridge(provider: SDKProvider, grace: TimeInterval = SDKRuntimeManager.terminationGrace) async {
        guard var state = bridges[provider] else { return }
        state.shutdownRequested = true
        bridges[provider] = state
        let process = state.process
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(grace)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning {
                #if canImport(Darwin)
                Darwin.kill(process.processIdentifier, SIGKILL)
                #endif
                let reapDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < reapDeadline {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        }
        state.stdoutTask?.cancel()
        state.stderrTask?.cancel()
        if let remaining = bridges[provider] {
            remaining.stdoutContinuation?.finish()
            lastBridgeStderrTails[provider] = remaining.stderrTail
            bridges[provider] = nil
            lastBridgeExits[provider] = process.terminationStatus
        }
    }

    public func terminateAllBridges() async {
        for provider in Array(bridges.keys) {
            await terminateBridge(provider: provider)
        }
    }

    public func shutdown() async {
        await terminateAllBridges()
    }

    private func runCapturingProcess(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeout: TimeInterval,
        logKey: SDKProvider,
        progress: (@Sendable (String) -> Void)?
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task {
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    self.appendInstallLine(provider: logKey, line: line, progress: progress)
                }
            } catch {  }
        }
        let stderrTask = Task {
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    self.appendInstallLine(provider: logKey, line: line, progress: progress)
                }
            } catch {  }
        }

        do {
            try process.run()
        } catch {
            stdoutTask.cancel(); stderrTask.cancel()
            throw SDKRuntimeError.processLaunchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            if Task.isCancelled {
                process.terminate()
                try? await Task.sleep(nanoseconds: 500_000_000)
                if process.isRunning {
                    #if canImport(Darwin)
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    #endif
                }
                stdoutTask.cancel(); stderrTask.cancel()
                throw SDKRuntimeError.installCancelled(logKey)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if process.isRunning {
            process.terminate()
            try? await Task.sleep(nanoseconds: 500_000_000)
            if process.isRunning {
                #if canImport(Darwin)
                Darwin.kill(process.processIdentifier, SIGKILL)
                #endif
            }
            stdoutTask.cancel(); stderrTask.cancel()
            throw SDKRuntimeError.installTimeout(logKey)
        }
        stdoutTask.cancel(); stderrTask.cancel()
        return process.terminationStatus
    }

    private func appendInstallLine(provider: SDKProvider, line: String, progress: (@Sendable (String) -> Void)?) {
        var log = installLogs[provider] ?? []
        log.append(line)
        if log.count > 500 { log.removeFirst(log.count - 500) }
        installLogs[provider] = log
        progress?(line)
    }
}

final class BufferWrapper: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
    }

    func popLine() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            return line
        }
        return nil
    }
}
