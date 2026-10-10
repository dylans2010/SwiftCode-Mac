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

        // Generate a unique socket path in the per-user temporary directory (not
        // world-readable /tmp). AF_UNIX paths are limited to 104 bytes.
        let tempSocket = Self.makeSocketPath()
        if FileManager.default.fileExists(atPath: tempSocket) {
            try? FileManager.default.removeItem(atPath: tempSocket)
        }
        self.socketPath = tempSocket

        let proc = Process()
        // The bridge exits on its own when this PID disappears (crash/force quit).
        let parentPID = String(ProcessInfo.processInfo.processIdentifier)

        // If bundled launcher executable exists, use it; otherwise locate host Python 3
        if FileManager.default.isExecutableFile(atPath: launcherURL.path) {
            proc.executableURL = launcherURL
            proc.arguments = [mainScriptURL.path, "--socket-path", tempSocket, "--parent-pid", parentPID]
        } else {
            let hostPython = findHostPython()
            guard let hostPython = hostPython else {
                throw GoogleCloudSDKError.pythonMissing("No Python 3 interpreter found on system.")
            }
            proc.executableURL = URL(fileURLWithPath: hostPython)
            proc.arguments = [mainScriptURL.path, "--socket-path", tempSocket, "--parent-pid", parentPID]
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
        if FileManager.default.isExecutableFile(atPath: harnessURL.path) {
            env["ANTIGRAVITY_HARNESS_PATH"] = harnessURL.path
        }
        // When only localharness.gz is bundled, the bridge unpacks it here instead
        // of writing into the signed (and possibly read-only) app bundle.
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            env["SWIFTCODE_SDK_SUPPORT_DIR"] = appSupport.appendingPathComponent("SwiftCode/AntigravityRuntime", isDirectory: true).path
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
            let pid = p.processIdentifier
            logger.info("Antigravity process terminated with exit code: \(exitCode)")
            Task { [weak self] in
                // Pass the socket that belonged to *this* process so a late
                // termination of an old process never deletes a newer socket.
                await self?.handleTermination(exitCode: exitCode, pid: pid, socket: tempSocket)
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

    private func handleTermination(exitCode: Int32, pid: Int32, socket: String) {
        if FileManager.default.fileExists(atPath: socket) {
            try? FileManager.default.removeItem(atPath: socket)
        }

        // Only reset shared state if the process that exited is still the current one.
        if let current = process, current.processIdentifier == pid {
            stdoutTask?.cancel()
            stderrTask?.cancel()
            stdoutTask = nil
            stderrTask = nil
            process = nil
            if socketPath == socket {
                socketPath = nil
            }
        } else if process != nil {
            return
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

    /// Stops the process gracefully (SIGTERM), escalating to SIGKILL for the
    /// whole bridge process group if it has not exited after a grace period.
    public func stop() {
        if let proc = process, proc.isRunning {
            let pid = proc.processIdentifier
            proc.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
                if Darwin.kill(pid, 0) == 0 {
                    logger.warning("Antigravity bridge (PID \(pid)) ignored SIGTERM; sending SIGKILL")
                    // The bridge leads its own process group; take harness children with it.
                    Darwin.kill(-pid, SIGKILL)
                    Darwin.kill(pid, SIGKILL)
                }
            }
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
            Darwin.kill(-proc.processIdentifier, SIGKILL)
            Darwin.kill(proc.processIdentifier, SIGKILL)
        }
        stop()
    }

    /// Synchronous best-effort termination for app shutdown, where there is no
    /// time to await the actor. Safe to call from any thread.
    public static func terminateSynchronously(pid: Int32) {
        guard pid > 0 else { return }
        Darwin.kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if Darwin.kill(pid, 0) != 0 { return }
            usleep(50_000)
        }
        Darwin.kill(-pid, SIGKILL)
        Darwin.kill(pid, SIGKILL)
    }

    /// Builds a short, per-user socket path that fits in sockaddr_un.sun_path.
    private static func makeSocketPath() -> String {
        let name = "sc-ag-\(UUID().uuidString.prefix(8)).sock"
        let tempDir = FileManager.default.temporaryDirectory.path
        let candidate = (tempDir as NSString).appendingPathComponent(name)
        if candidate.utf8.count < 100 {
            return candidate
        }
        return "/tmp/swiftcode-\(getuid())-\(name)"
    }
}
