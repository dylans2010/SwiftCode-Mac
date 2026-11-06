//
//  GoogleCloudSDKProcess.swift
//  SwiftCode
//
//  Subprocess lifecycle manager for the Google Antigravity Python bridge.
//
//  Ported from Legacy (Dylan's own code; direct port authorised
//  under MIT):
//    SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKProcess.swift
//
//  Adaptations for the destination:
//  - SDK resolution: Legacy step 3 read the active workspace via
//    `ProjectSessionStore.shared.activeProject`, which does not
//    exist in the destination. The staged bridge lives at
//    `SwiftCodeGoogleAuth/Resources/GoogleCloudSDK/bridge/main.py`
//    (see GOOGLE-SWIFT-FRAGMENT.md / PYTHON-BRIDGE-FRAGMENT.md),
//    so resolution now starts at this target's resource bundle
//    (`Bundle.module`, which requires the `resources:
//    [.copy("Resources/GoogleCloudSDK")]` declaration on the
//    SwiftCodeGoogleAuth target at integration time), then falls
//    back to the app bundle's `Google Cloud SDK` resource
//    directory, a `GOOGLE_CLOUD_SDK_DIR` environment override, the
//    current working directory, and Application Support. No user
//    home path is hardcoded.
//  - Credentials: Legacy read the Gemini API key from
//    `KeychainService.shared` / `LLMProvider.google`, which do not
//    exist in the destination. API-key mode now reads
//    `SecretAccount.geminiKey` from the destination
//    `defaultSecretStore()` (SwiftCodeAssistant). OAuth mode still
//    injects `GOOGLE_OAUTH_ACCESS_TOKEN` from
//    `GoogleAccountAuthService.shared.getValidAccessToken()`, with
//    the same credential-kind separation (never both, never a
//    fallback across kinds).
//  - `resolveSDKDirectory` keeps its `@MainActor` isolation; the
//    `UserDefaults` keys (`antigravity_execution_mode`,
//    `assist_google_auth_mode`) are read directly, as in Legacy.

import Foundation
import os

#if canImport(Darwin)
import Darwin
#endif

import SwiftCodeAssistant

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

    /// Resolves the Google Cloud SDK root directory: the directory
    /// containing `bridge/main.py`.
    @MainActor
    public static func resolveSDKDirectory() -> URL? {
        let fm = FileManager.default
        func hasBridge(_ dir: URL) -> Bool {
            fm.fileExists(atPath: dir.appendingPathComponent("bridge/main.py").path)
        }

        // 1. This target's resource bundle (SPM `.copy("Resources/GoogleCloudSDK")`).
        let moduleSDK = Bundle.module.resourceURL?.appendingPathComponent("GoogleCloudSDK", isDirectory: true)
        if let moduleSDK, hasBridge(moduleSDK) {
            return moduleSDK
        }

        // 2. Packaged App Bundle: SwiftCode.app/Contents/Resources/Google Cloud SDK
        if let bundleResources = Bundle.main.resourceURL {
            let bundleSDK = bundleResources.appendingPathComponent("Google Cloud SDK", isDirectory: true)
            if hasBridge(bundleSDK) {
                return bundleSDK
            }
        }

        // 3. Main Bundle direct resource path
        if let path = Bundle.main.path(forResource: "Google Cloud SDK", ofType: nil) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if hasBridge(url) {
                return url
            }
        }

        // 4. Explicit environment override (development / provisioning).
        if let overrideDir = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SDK_DIR"],
           !overrideDir.isEmpty {
            let url = URL(fileURLWithPath: overrideDir, isDirectory: true)
            if hasBridge(url) {
                return url
            }
        }

        // 5. Current working directory fallback
        let cwdSDK = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SwiftCode/Resources/Google Cloud SDK", isDirectory: true)
        if hasBridge(cwdSDK) {
            return cwdSDK
        }

        // 6. Application Support managed location
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appSupportSDK = appSupport.appendingPathComponent("SwiftCode/GoogleCloudSDK", isDirectory: true)
            if hasBridge(appSupportSDK) {
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
        let mode = UserDefaults.standard.string(forKey: "antigravity_execution_mode") ?? "resources"
        let directBinaryPath = findDownloadedAntigravityBinary(sdkDir: sdkDir)

        if mode == "resources", FileManager.default.isExecutableFile(atPath: launcherURL.path) {
            // Use the runtime's version-checked interpreter, not an arbitrary
            // host Python incompatible with the bundled native extensions.
            proc.executableURL = launcherURL
            proc.arguments = ["-m", "google.antigravity", "--socket-path", tempSocket]
            logger.info("Launching bundled Antigravity package via its Python launcher")
        } else if mode == "resources", let binPath = directBinaryPath {
            proc.executableURL = URL(fileURLWithPath: binPath)
            proc.arguments = ["--socket-path", tempSocket]
            logger.info("Launching downloaded Antigravity binary: \(binPath)")
        } else {
            // Bridge mode
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

        // Configure environment
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

        // Credential-kind separation at the process boundary: in Google account
        // mode the bridge must never see an API key, even when the OAuth token
        // is currently unavailable. Falling back to GEMINI_API_KEY here would
        // silently switch the session from account authentication to API-key
        // authentication; instead the bridge raises an explicit "no
        // credentials" error naming the missing sign-in.
        // Note: UserDefaults is read directly (rather than AppSettings.shared,
        // which is @MainActor) because this runs on the process actor.
        let googleAuthMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? "google_oauth"
        let isOAuthMode = googleAuthMode == "google_oauth"
        // M-10: GOOGLE_OAUTH_ACCESS_TOKEN is only injected in OAuth mode. In
        // API-key mode a lingering valid OAuth token in the process
        // environment would otherwise hijack sessions Swift explicitly
        // configured for API-key auth (credential-kind separation).
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
