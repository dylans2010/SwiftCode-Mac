import Foundation
import os

#if canImport(Darwin)
import Darwin
#endif

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

    @MainActor
    public static func resolveSDKDirectory() -> URL? {
        let fm = FileManager.default
        func hasBridge(_ dir: URL) -> Bool {
            fm.fileExists(atPath: dir.appendingPathComponent("bridge/main.py").path)
        }

        let moduleSDK = Bundle.module.resourceURL?.appendingPathComponent("GoogleCloudSDK", isDirectory: true)
        if let moduleSDK, hasBridge(moduleSDK) {
            return moduleSDK
        }

        if let bundleResources = Bundle.main.resourceURL {
            let bundleSDK = bundleResources.appendingPathComponent("Google Cloud SDK", isDirectory: true)
            if hasBridge(bundleSDK) {
                return bundleSDK
            }
        }

        if let path = Bundle.main.path(forResource: "Google Cloud SDK", ofType: nil) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if hasBridge(url) {
                return url
            }
        }

        if let overrideDir = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SDK_DIR"],
           !overrideDir.isEmpty {
            let url = URL(fileURLWithPath: overrideDir, isDirectory: true)
            if hasBridge(url) {
                return url
            }
        }

        let cwdSDK = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SwiftCode/Resources/Google Cloud SDK", isDirectory: true)
        if hasBridge(cwdSDK) {
            return cwdSDK
        }

        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appSupportSDK = appSupport.appendingPathComponent("SwiftCode/GoogleCloudSDK", isDirectory: true)
            if hasBridge(appSupportSDK) {
                return appSupportSDK
            }
        }

        return nil
    }

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

        let tempSocket = "/tmp/swiftcode-antigravity-\(UUID().uuidString.prefix(8)).sock"
        if FileManager.default.fileExists(atPath: tempSocket) {
            try? FileManager.default.removeItem(atPath: tempSocket)
        }
        self.socketPath = tempSocket

        let proc = Process()
        let mode = UserDefaults.standard.string(forKey: "antigravity_execution_mode") ?? "resources"
        let directBinaryPath = findDownloadedAntigravityBinary(sdkDir: sdkDir)

        if mode == "resources", FileManager.default.isExecutableFile(atPath: launcherURL.path) {
            proc.executableURL = launcherURL
            proc.arguments = ["-m", "google.antigravity", "--socket-path", tempSocket]
            logger.info("Launching bundled Antigravity package via its Python launcher")
        } else if mode == "resources", let binPath = directBinaryPath {
            proc.executableURL = URL(fileURLWithPath: binPath)
            proc.arguments = ["--socket-path", tempSocket]
            logger.info("Launching downloaded Antigravity binary: \(binPath)")
        } else {
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
            logger.info("Launching Antigravity Python bridge")
        }

        var env = ProcessInfo.processInfo.environment
        let sitePackages = sdkDir.appendingPathComponent("runtime/lib/python3.14/site-packages").path

        if let existing = env["PYTHONPATH"] {
            env["PYTHONPATH"] = "\(sitePackages):\(existing)"
        } else {
            env["PYTHONPATH"] = sitePackages
        }
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"

        let harnessURL = sdkDir.appendingPathComponent("runtime/lib/python3.14/site-packages/google/antigravity/bin/localharness")
        if FileManager.default.fileExists(atPath: harnessURL.path) {
            env["ANTIGRAVITY_HARNESS_PATH"] = harnessURL.path
        }

        let googleAuthMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? "google_oauth"
        let isOAuthMode = googleAuthMode == "google_oauth"
        env.removeValue(forKey: "GOOGLE_OAUTH_ACCESS_TOKEN")
        env.removeValue(forKey: "GEMINI_API_KEY")
        env.removeValue(forKey: "GOOGLE_API_KEY")
        if isOAuthMode, let oauthToken = await GoogleAccountAuthService.shared.getValidAccessToken(), !oauthToken.isEmpty {
            env["GOOGLE_OAUTH_ACCESS_TOKEN"] = oauthToken
        } else if !isOAuthMode, let apiKey = defaultSecretStore().readString(SecretAccount.geminiKey), !apiKey.isEmpty {
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

        let instanceSocket = tempSocket
        proc.terminationHandler = { [weak self] p in
            let exitCode = p.terminationStatus
            logger.info("Antigravity process terminated with exit code: \(exitCode)")
            Task { [weak self] in
                await self?.handleTermination(socketPathToDelete: instanceSocket, exitCode: exitCode)
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

    private func findDownloadedAntigravityBinary(sdkDir: URL) -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "\(homeDir)/.local/bin/google-antigravity",
            "\(homeDir)/Library/Python/3.14/bin/google-antigravity",
            "/opt/homebrew/bin/google-antigravity",
            "/usr/local/bin/google-antigravity",
            sdkDir.appendingPathComponent("runtime/bin/google-antigravity").path
        ]

        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
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

    private func handleTermination(socketPathToDelete: String?, exitCode: Int32) {
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        if let sock = socketPathToDelete, FileManager.default.fileExists(atPath: sock) {
            try? FileManager.default.removeItem(atPath: sock)
        }
        if self.socketPath == socketPathToDelete {
            self.socketPath = nil
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

    public func kill() {
        if let proc = process, proc.isRunning {
            Darwin.kill(proc.processIdentifier, SIGKILL)
        }
        stop()
    }
}
