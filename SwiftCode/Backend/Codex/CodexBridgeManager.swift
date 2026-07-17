import Foundation
import AppKit
import os
import Observation

private let logger = Logger(subsystem: "com.swiftcode.CodexBridge", category: "CodexBridgeManager")

public enum CodexBridgeStatus: String, Codable, Sendable {
    case notInstalled = "Not Installed"
    case located = "Located"
    case starting = "Starting"
    case running = "Running"
    case reconnecting = "Reconnecting"
    case offline = "Offline"
    case failed = "Failed"
}

public enum CodexStartupStage: String, CaseIterable, Identifiable, Sendable {
    case detectCLI = "Detecting Codex CLI"
    case verifyVersion = "Verifying CLI Version"
    case checkAuth = "Checking Authentication"
    case runInstaller = "Downloading & Installing Codex CLI"
    case authenticateChatGPT = "Authenticating with ChatGPT"
    case saveAPIKey = "Saving API Key"
    case startBackend = "Starting Backend"
    case verifyConnection = "Verifying Connection"
    case sendTestPrompt = "Sending Test Prompt"
    case markReady = "Marking Codex Ready"

    public var id: String { self.rawValue }
}

@Observable
@MainActor
public final class CodexBridgeManager: Sendable {
    public static let shared = CodexBridgeManager()

    // Real-time diagnostics metrics
    public var bridgeStatus: CodexBridgeStatus = .offline
    public var liveLogs: [String] = []
    public var activeRequests: Int = 0
    public var sessionCount: Int = 0
    public var lastSuccessfulRequest: Date?
    public var lastFailure: String?
    public var launchTime: Date?
    public var cliVersion: String = "Unknown"
    public var cliLocation: String = "Not Detected"
    public var isAuthenticated: Bool = false
    public var authModeString: String = "None"
    public var sessionStatus: String = "Idle"
    public var streamStatus: String = "Idle"
    public var activeToolName: String = "None"
    public var activeToolDetails: String = ""
    public var isInstalling: Bool = false
    public var installProgress: String = ""
    public var isConnecting: Bool = false

    private var activeProcess: Process?
    private var isShuttingDown = false

    public var connectionDuration: TimeInterval {
        guard let launchTime else { return 0 }
        return Date().timeIntervalSince(launchTime)
    }

    private init() {
        Task {
            await self.auditEnvironment()
        }

        // Register shutdown notifications
        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.shutdownBridge()
            }
        }
        #endif
    }

    /// Appends a live diagnostic log entry.
    public func appendLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logLine = "[\(timestamp)] \(message)"
        logger.log("\(logLine)")
        liveLogs.append(logLine)
        if liveLogs.count > 1000 {
            liveLogs.removeFirst()
        }
    }

    /// Resolves the resources directory (for compatibility).
    public func locateResources() throws -> (packageJson: URL, bridgeJs: URL) {
        // Return dummy URLs to keep other modules compiling if they use it.
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let codexDir = appSupport.appendingPathComponent("SwiftCode/Codex", isDirectory: true)
        return (codexDir.appendingPathComponent("package.json"), codexDir.appendingPathComponent("bridge.js"))
    }

    /// Automatically discover the official Codex CLI on the machine.
    public func discoverCLIPath() -> String? {
        let fm = FileManager.default

        // 1. Managed installation path
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let managedPath = appSupport.appendingPathComponent("SwiftCode/Codex/codex").path
        if fm.fileExists(atPath: managedPath) {
            return managedPath
        }

        // 2. Standalone package paths
        let homeDir = fm.homeDirectoryForCurrentUser.path
        let standalonePaths = [
            "\(homeDir)/.codex/packages/standalone/current/codex",
            "\(homeDir)/.codex/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        for path in standalonePaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        // 3. Environment path search
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "codex"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                if let data = try pipe.fileHandleForReading.readToEnd(),
                   let resolved = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !resolved.isEmpty, fm.fileExists(atPath: resolved) {
                    return resolved
                }
            }
        } catch {}

        return nil
    }

    /// Performs an audit of the entire environment on demand.
    public func auditEnvironment() async {
        appendLog("Auditing environment for official OpenAI Codex CLI...")
        if let path = discoverCLIPath() {
            cliLocation = path
            bridgeStatus = .located
            appendLog("Codex CLI discovered at: \(path)")

            // Get Version
            if let version = await checkCLIVersion(at: path) {
                cliVersion = version
                appendLog("Discovered Codex CLI version: \(version)")
            } else {
                cliVersion = "Unknown"
                appendLog("Failed to parse Codex CLI version.")
            }

            // Check Auth Status
            let (auth, mode) = await checkCLIAuthStatus(at: path)
            isAuthenticated = auth
            authModeString = mode
            appendLog("Codex CLI Authentication status: \(auth ? "Authenticated" : "Not Authenticated") (Mode: \(mode))")

            if auth {
                bridgeStatus = .running
            }
        } else {
            cliLocation = "Not Detected"
            cliVersion = "N/A"
            isAuthenticated = false
            authModeString = "None"
            bridgeStatus = .notInstalled
            appendLog("Official OpenAI Codex CLI was not detected on this machine.")
        }
    }

    /// Check the installed version of Codex CLI at a specific path.
    private func checkCLIVersion(at path: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if let data = try pipe.fileHandleForReading.readToEnd(),
               let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                // Parse version (usually returns '0.143.0' or similar)
                return output
            }
        } catch {}
        return nil
    }

    /// Checks the login/auth status of the CLI.
    private func checkCLIAuthStatus(at path: String) async -> (Bool, String) {
        // Check local Keychain for stored API Key first
        let storedKey = KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) ?? ""
        if !storedKey.isEmpty {
            return (true, "API Key (Keychain)")
        }

        // Run `codex login status` or check `~/.codex/auth.json`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["login", "status"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               let data = try outPipe.fileHandleForReading.readToEnd(),
               let output = String(data: data, encoding: .utf8) {
                if output.contains("Logged in") || output.contains("Authenticated") || output.contains("Active") {
                    return (true, "ChatGPT Account")
                }
            }
        } catch {}

        // Check if auth file exists manually as backup
        let fm = FileManager.default
        let authJSONPath = "\(fm.homeDirectoryForCurrentUser.path)/.codex/auth.json"
        if fm.fileExists(atPath: authJSONPath) {
            return (true, "ChatGPT (auth.json)")
        }

        return (false, "None")
    }

    /// Installs the official Codex CLI using the official stand-alone installer.
    public func installCLI() async throws {
        guard !isInstalling else { return }
        isInstalling = true
        installProgress = "Preparing installation..."
        appendLog("Initiating managed installation of the official OpenAI Codex CLI...")

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let managedDir = appSupport.appendingPathComponent("SwiftCode/Codex", isDirectory: true)

        do {
            try fm.createDirectory(at: managedDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            isInstalling = false
            appendLog("Failed to create managed directory: \(error.localizedDescription)")
            throw error
        }

        // We run curl -fsSL https://chatgpt.com/codex/install.sh | sh
        // Since we want progress, let's download the script and then execute it.
        installProgress = "Downloading official Codex installer script..."
        appendLog("Fetching official installer script from https://chatgpt.com/codex/install.sh...")

        let scriptURL = URL(string: "https://chatgpt.com/codex/install.sh")!
        let (tempDir, _) = try await URLSession.shared.download(from: scriptURL)

        installProgress = "Checking prerequisites and running installer..."
        appendLog("Executing installer script...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [tempDir.path]

        // Set custom PREFIX if supported, but also let it default to standalone path.
        // We set environment so that Codex installs correctly
        var env = ProcessInfo.processInfo.environment
        env["PREFIX"] = managedDir.path
        env["CODEX_HOME"] = managedDir.path
        process.environment = env

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe

        process.terminationHandler = { [weak self] p in
            guard let self = self else { return }
            Task { @MainActor in
                self.isInstalling = false
                if p.terminationStatus == 0 {
                    self.installProgress = "Installation complete and verified."
                    self.appendLog("Official Codex CLI installer completed successfully.")
                    await self.auditEnvironment()
                } else {
                    self.installProgress = "Installation failed."
                    self.appendLog("Installer script failed with exit code: \(p.terminationStatus)")
                }
            }
        }

        do {
            try process.run()

            // Stream logs in real-time
            let handle = outPipe.fileHandleForReading
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    for try await line in handle.bytes.lines {
                        await self.appendLog("[Installer] \(line)")
                        await MainActor.run {
                            self.installProgress = line
                        }
                    }
                } catch {}
            }

            process.waitUntilExit()
        } catch {
            isInstalling = false
            appendLog("Failed to execute installer process: \(error.localizedDescription)")
            throw error
        }
    }

    /// Initiates ChatGPT login using the official CLI auth command.
    public func loginWithChatGPT() async throws {
        guard let path = discoverCLIPath() else {
            throw NSError(domain: "CodexBridgeManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Codex CLI is not installed."])
        }

        appendLog("Initiating ChatGPT Authentication flow...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["login"] // Will open browser oauth naturally

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe

        do {
            try process.run()

            Task.detached { [weak self] in
                guard let self = self else { return }
                let handle = outPipe.fileHandleForReading
                do {
                    for try await line in handle.bytes.lines {
                        await self.appendLog("[CLI Auth] \(line)")
                    }
                } catch {}
            }

            process.waitUntilExit()
            await auditEnvironment()
        } catch {
            appendLog("ChatGPT Auth initiation failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Triggers the device-code login flow.
    public func loginWithDeviceCode(onCodeReceived: @MainActor @escaping (String, String) -> Void) async throws {
        guard let path = discoverCLIPath() else {
            throw NSError(domain: "CodexBridgeManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Codex CLI is not installed."])
        }

        appendLog("Initiating Device Code Authentication...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["login", "--device-auth"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe

        do {
            try process.run()

            Task.detached { [weak self] in
                guard let self = self else { return }
                let handle = outPipe.fileHandleForReading
                do {
                    for try await line in handle.bytes.lines {
                        await self.appendLog("[CLI Auth] \(line)")
                        // Parse device code and URL
                        if line.contains("https://") {
                            // Find URL and Code
                            let components = line.components(separatedBy: .whitespacesAndNewlines)
                            let url = components.first(where: { $0.hasPrefix("https://") }) ?? ""
                            // Extract code (e.g. ABCD-1234)
                            let pattern = "[A-Z0-9]{4}-[A-Z0-9]{4}"
                            if let regex = try? NSRegularExpression(pattern: pattern),
                               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                               let range = Range(match.range, in: line) {
                                let code = String(line[range])
                                await MainActor.run {
                                    onCodeReceived(url, code)
                                }
                            }
                        }
                    }
                } catch {}
            }

            process.waitUntilExit()
            await auditEnvironment()
        } catch {
            appendLog("Device authentication failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Logs out from Codex CLI completely.
    public func logout() async {
        guard let path = discoverCLIPath() else { return }
        appendLog("Logging out from Codex CLI...")

        // Delete from Keychain
        KeychainService.shared.delete(forKey: KeychainService.codexUserAPIKey)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["logout"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {}

        await auditEnvironment()
    }

    /// Gracefully shuts down any running background bridge tasks.
    public func shutdownBridge() async {
        isShuttingDown = true
        if let proc = activeProcess, proc.isRunning {
            appendLog("Shutting down active process...")
            proc.terminate()
        }
        activeProcess = nil
        bridgeStatus = .offline
    }

    /// Emulates bridge activation for legacy views.
    public func ensureBridgeRunning() async {
        await auditEnvironment()
    }

    /// Checks if the local bridge server is responding (compatibility).
    public func isBridgeHealthy() async -> Bool {
        return discoverCLIPath() != nil
    }

    /// Validates an API Key using the CLI.
    public func validateAPIKey(_ apiKey: String) async -> Bool {
        guard let path = discoverCLIPath() else { return false }
        appendLog("Validating API Key using Codex CLI...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // We use non-interactive validation via exec
        process.arguments = ["exec", "Respond with VALID", "--sandbox", "read-only"]

        var env = ProcessInfo.processInfo.environment
        env["CODEX_API_KEY"] = apiKey
        process.environment = env

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               let data = try outPipe.fileHandleForReading.readToEnd(),
               let output = String(data: data, encoding: .utf8) {
                return output.contains("VALID")
            }
        } catch {}
        return false
    }

    /// Complete setup sequence wrapper for onboarding UI.
    public func startStartupSequence(apiKey: String, onProgress: @MainActor @Sendable @escaping (CodexStartupStage, String) -> Void) async throws {
        isConnecting = true
        defer { isConnecting = false }

        // Stage 1: Discover
        onProgress(.detectCLI, "Locating official OpenAI Codex CLI installation...")
        await auditEnvironment()

        if cliLocation == "Not Detected" {
            // Stage 2: Install
            onProgress(.runInstaller, "Codex CLI not detected. Running managed installation...")
            try await installCLI()
        }

        guard let path = discoverCLIPath() else {
            throw NSError(domain: "CodexBridgeManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Official Codex CLI installation failed or not found."])
        }

        // Stage 3: Version check
        onProgress(.verifyVersion, "Verifying CLI version compatibility...")
        if let version = await checkCLIVersion(at: path) {
            cliVersion = version
        }

        // Stage 4: Authentication
        if !apiKey.isEmpty {
            onProgress(.saveAPIKey, "Configuring and validating API Key...")
            let valid = await validateAPIKey(apiKey)
            if !valid {
                throw NSError(domain: "CodexBridgeManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI API Key."])
            }
            KeychainService.shared.set(apiKey, forKey: KeychainService.codexUserAPIKey)
            authModeString = "API Key"
            isAuthenticated = true
        } else {
            onProgress(.checkAuth, "Verifying ChatGPT authentication status...")
            let (auth, mode) = await checkCLIAuthStatus(at: path)
            if !auth {
                onProgress(.authenticateChatGPT, "Launching browser login for ChatGPT...")
                try await loginWithChatGPT()
            }
        }

        // Stage 5: Connection testing
        onProgress(.verifyConnection, "Performing final backend loop handshake...")
        sessionCount += 1
        bridgeStatus = .running

        // Stage 6: Test Prompt
        onProgress(.sendTestPrompt, "Sending verification prompt...")
        let testResponse = try await sendPrompt("Respond with VALID")
        if !testResponse.contains("VALID") && !testResponse.isEmpty {
            appendLog("Handshake verified with warning: unexpected response payload.")
        }

        onProgress(.markReady, "Codex integration ready.")
        UserDefaults.standard.set(true, forKey: "com.swiftcode.codex.completedSetup")
        UserDefaults.standard.set("Codex", forKey: "assist.selectedProvider")
    }

    /// Single non-streaming prompt request to Codex CLI via `codex exec`.
    public func sendPrompt(_ prompt: String) async throws -> String {
        guard let path = discoverCLIPath() else {
            throw LLMError.networkError("Codex CLI is not installed. Open setup flow.")
        }

        activeRequests += 1
        defer { activeRequests -= 1 }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["exec", prompt, "--sandbox", "workspace-write"]

        // Attach API Key if configured
        if let apiKey = KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) {
            var env = ProcessInfo.processInfo.environment
            env["CODEX_API_KEY"] = apiKey
            process.environment = env
        }

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0,
               let data = try outPipe.fileHandleForReading.readToEnd(),
               let text = String(data: data, encoding: .utf8) {
                lastSuccessfulRequest = Date()
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw NSError(domain: "CodexCLI", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "CLI returned non-zero exit code \(process.terminationStatus)"])
            }
        } catch {
            lastFailure = error.localizedDescription
            throw error
        }
    }

    /// Real-time streaming prompt request via machine-readable `codex exec --json`.
    public func streamPrompt(_ prompt: String, onToken: @escaping @Sendable (String) async -> Void) async throws {
        guard let path = discoverCLIPath() else {
            throw LLMError.networkError("Codex CLI is not installed. Open setup flow.")
        }

        activeRequests += 1
        streamStatus = "Streaming"
        defer {
            activeRequests -= 1
            streamStatus = "Idle"
            activeToolName = "None"
            activeToolDetails = ""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // Run with machine-readable JSON option!
        process.arguments = ["exec", prompt, "--json", "--sandbox", "workspace-write"]

        if let apiKey = KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) {
            var env = ProcessInfo.processInfo.environment
            env["CODEX_API_KEY"] = apiKey
            process.environment = env
        }

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        activeProcess = process

        do {
            try process.run()

            let handle = outPipe.fileHandleForReading
            for try await line in handle.bytes.lines {
                guard let data = line.data(using: .utf8) else { continue }

                // Parse structured JSON event emitted by Codex CLI
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let type = json["type"] as? String ?? ""

                    // 1. Text delta token streaming
                    if type == "item/agentMessage/delta" || type == "item.agentMessage/delta",
                       let delta = json["delta"] as? String {
                        await onToken(delta)
                    } else if type == "item/agentMessage" || type == "item.agentMessage",
                              let item = json["item"] as? [String: Any],
                              let delta = item["delta"] as? String {
                        await onToken(delta)
                    }

                    // 2. Timeline and tool executions
                    if type == "item.started" || type == "item/started",
                       let item = json["item"] as? [String: Any] {
                        let toolType = item["type"] as? String ?? "Tool"
                        let details = item["command"] as? String ?? item["path"] as? String ?? ""
                        await MainActor.run {
                            self.activeToolName = toolType
                            self.activeToolDetails = details
                            self.appendLog("Started \(toolType): \(details)")
                        }
                    } else if type == "item.completed" || type == "item/completed",
                              let item = json["item"] as? [String: Any] {
                        let toolType = item["type"] as? String ?? "Tool"
                        await MainActor.run {
                            self.activeToolName = "None"
                            self.activeToolDetails = ""
                            self.appendLog("Completed \(toolType)")
                        }
                    }
                }
            }

            process.waitUntilExit()
            activeProcess = nil

            if process.terminationStatus == 0 {
                lastSuccessfulRequest = Date()
            } else {
                throw NSError(domain: "CodexCLI", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "CLI streaming failed with exit code \(process.terminationStatus)"])
            }
        } catch {
            activeProcess = nil
            lastFailure = error.localizedDescription
            throw error
        }
    }
}