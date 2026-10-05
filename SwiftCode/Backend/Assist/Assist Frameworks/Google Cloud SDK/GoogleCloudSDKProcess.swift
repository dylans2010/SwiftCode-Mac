//
//  GoogleCloudSDKProcess.swift
//  SwiftCode
//
//  Subprocess lifecycle manager for the Google Antigravity Python bridge.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.GoogleCloudSDK", category: "GoogleCloudSDKProcess")

public actor GoogleCloudSDKProcess {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private(set) public var socketPath: String?
    private(set) public var liveLogs: [String] = []
    private var terminationHandlers: [UUID: @Sendable (Int32) -> Void] = [:]

    public init() {}

    deinit {
        process?.terminate()
    }

    public var isRunning: Bool {
        process?.isRunning ?? false
    }

    public var processIdentifier: Int32? {
        process?.processIdentifier
    }

    /// Resolves the Google Cloud SDK root directory across bundle, workspace, and Application Support locations.
    @MainActor
    public static func resolveSDKDirectory() -> URL? {
        let fm = FileManager.default

        // 1. Packaged App Bundle: SwiftCode.app/Contents/Resources/Google Cloud SDK
        if let bundleResources = Bundle.main.resourceURL {
            let bundleSDK = bundleResources.appendingPathComponent("Google Cloud SDK", isDirectory: true)
            if fm.fileExists(atPath: bundleSDK.appendingPathComponent("bridge/main.py").path) {
                return bundleSDK
            }
        }

        // 2. Main Bundle direct resource path
        if let path = Bundle.main.path(forResource: "Google Cloud SDK", ofType: nil) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if fm.fileExists(atPath: url.appendingPathComponent("bridge/main.py").path) {
                return url
            }
        }

        // 3. Active Workspace / Development path
        if let projectURL = ProjectSessionStore.shared.activeProject?.directoryURL {
            let devSDK = projectURL.appendingPathComponent("SwiftCode/Resources/Google Cloud SDK", isDirectory: true)
            if fm.fileExists(atPath: devSDK.appendingPathComponent("bridge/main.py").path) {
                return devSDK
            }
        }

        // 4. Current working directory fallback
        let cwdSDK = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SwiftCode/Resources/Google Cloud SDK", isDirectory: true)
        if fm.fileExists(atPath: cwdSDK.appendingPathComponent("bridge/main.py").path) {
            return cwdSDK
        }

        // 5. Application Support managed location
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appSupportSDK = appSupport.appendingPathComponent("SwiftCode/GoogleCloudSDK", isDirectory: true)
            if fm.fileExists(atPath: appSupportSDK.appendingPathComponent("bridge/main.py").path) {
                return appSupportSDK
            }
        }

        return nil
    }

    /// Launches the Python bridge subprocess and returns the Unix domain socket path.
    public func start() async throws -> String {
        if isRunning, let path = socketPath {
            return path
        }

        stop()

        guard let sdkDir = await Self.resolveSDKDirectory() else {
            throw GoogleCloudSDKError.runtimeNotFound("Could not locate 'Google Cloud SDK' in application bundle or resources.")
        }

        let launcherURL = sdkDir.appendingPathComponent("runtime/bin/python3")
        let mainScriptURL = sdkDir.appendingPathComponent("bridge/main.py")

        guard FileManager.default.fileExists(atPath: mainScriptURL.path) else {
            throw GoogleCloudSDKError.runtimeNotFound("Bridge script missing at: \(mainScriptURL.path)")
        }

        // Generate unique socket path in temporary directory
        let tempSocket = "/tmp/swiftcode-antigravity-\(UUID().uuidString.prefix(8)).sock"
        if FileManager.default.fileExists(atPath: tempSocket) {
            try? FileManager.default.removeItem(atPath: tempSocket)
        }
        self.socketPath = tempSocket

        let proc = Process()

        // If bundled launcher executable exists, use it; otherwise locate host Python 3
        if FileManager.default.isExecutableFile(atPath: launcherURL.path) {
            proc.executableURL = launcherURL
            proc.arguments = [mainScriptURL.path, "--socket-path", tempSocket]
        } else {
            let hostPython = findHostPython()
            guard let hostPython = hostPython else {
                throw GoogleCloudSDKError.pythonMissing("No Python 3 interpreter found on system.")
            }
            proc.executableURL = URL(fileURLWithPath: hostPython)
            proc.arguments = [mainScriptURL.path, "--socket-path", tempSocket]
        }

        // Configure environment
        var env = ProcessInfo.processInfo.environment
        let sitePackages = sdkDir.appendingPathComponent("runtime/lib/python3.14/site-packages").path
        if let existing = env["PYTHONPATH"] {
            env["PYTHONPATH"] = "\(sitePackages):\(existing)"
        } else {
            env["PYTHONPATH"] = sitePackages
        }
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONNOUSERSITE"] = "1"

        let harnessURL = sdkDir.appendingPathComponent("runtime/lib/python3.14/site-packages/google/antigravity/bin/localharness")
        if FileManager.default.fileExists(atPath: harnessURL.path) {
            env["ANTIGRAVITY_HARNESS_PATH"] = harnessURL.path
        }

        if let apiKey = KeychainService.shared.get(forKey: LLMProvider.google.keychainKey), !apiKey.isEmpty {
            env["GEMINI_API_KEY"] = apiKey
        }

        proc.environment = env
        proc.currentDirectoryURL = sdkDir

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe

        proc.terminationHandler = { [weak self] p in
            let exitCode = p.terminationStatus
            logger.info("Antigravity process terminated with exit code: \(exitCode)")
            Task { [weak self] in
                await self?.handleTermination(exitCode: exitCode)
            }
        }

        do {
            try proc.run()
            self.process = proc
            logger.info("Launched Antigravity bridge process (PID: \(proc.processIdentifier)) listening on \(tempSocket)")
        } catch {
            throw GoogleCloudSDKError.processLaunchFailed(error.localizedDescription)
        }

        startLogStreaming(stdout: outPipe, stderr: errPipe)

        return tempSocket
    }

    private func findHostPython() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func startLogStreaming(stdout: Pipe, stderr: Pipe) {
        stdoutTask = Task.detached(priority: .utility) { [weak self] in
            do {
                for try await line in stdout.fileHandleForReading.bytes.lines {
                    await self?.appendLog("[OUT] \(line)")
                }
            } catch {
                await self?.appendLog("[OUT stream error] \(error.localizedDescription)")
            }
        }

        stderrTask = Task.detached(priority: .utility) { [weak self] in
            do {
                for try await line in stderr.fileHandleForReading.bytes.lines {
                    await self?.appendLog("[ERR] \(line)")
                }
            } catch {
                await self?.appendLog("[ERR stream error] \(error.localizedDescription)")
            }
        }
    }

    private func appendLog(_ message: String) {
        logger.debug("\(message)")
        liveLogs.append(message)
        if liveLogs.count > 1000 {
            liveLogs.removeFirst(liveLogs.count - 1000)
        }
    }

    private func handleTermination(exitCode: Int32) {
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        if let sock = socketPath, FileManager.default.fileExists(atPath: sock) {
            try? FileManager.default.removeItem(atPath: sock)
        }

        for (_, handler) in terminationHandlers {
            handler(exitCode)
        }
    }

    public func onTermination(handler: @escaping @Sendable (Int32) -> Void) -> UUID {
        let id = UUID()
        terminationHandlers[id] = handler
        return id
    }

    public func removeTerminationHandler(id: UUID) {
        terminationHandlers.removeValue(forKey: id)
    }

    /// Stops the process gracefully.
    public func stop() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil

        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        if let sock = socketPath, FileManager.default.fileExists(atPath: sock) {
            try? FileManager.default.removeItem(atPath: sock)
        }
        socketPath = nil
    }

    /// Forces process kill if it fails to exit cleanly.
    public func kill() {
        if let proc = process, proc.isRunning {
            Darwin.kill(proc.processIdentifier, SIGKILL)
        }
        stop()
    }
}
