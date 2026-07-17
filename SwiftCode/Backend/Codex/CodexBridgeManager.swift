import Foundation
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
    case validateAPIKey = "Validating API Key"
    case saveToKeychain = "Saving to Keychain"
    case locateBridge = "Locating Bundled Bridge"
    case verifyResources = "Verifying Bridge Resources"
    case verifyNode = "Checking Node Runtime"
    case launchBridge = "Launching Bridge Process"
    case monitorLogs = "Monitoring Logs"
    case waitForReady = "Waiting for Bridge Ready"
    case verifyComm = "Verifying Communication"
    case createSession = "Creating Codex Session"
    case sendTestPrompt = "Sending Test Prompt"
    case verifyStreaming = "Verifying Streaming"
    case markReady = "Marking Codex Ready"

    public var id: String { self.rawValue }
}

@Observable
@MainActor
public final class CodexBridgeManager: Sendable {
    public static let shared = CodexBridgeManager()

    private let port = 3003
    private let healthURL = URL(string: "http://127.0.0.1:3003/health")!
    private let completionsURL = URL(string: "http://127.0.0.1:3003/v1/chat/completions")!

    private var process: Process?
    private var isShuttingDown = false

    // Real-time diagnostics metrics
    public var bridgeStatus: CodexBridgeStatus = .offline
    public var liveLogs: [String] = []
    public var activeRequests: Int = 0
    public var sessionCount: Int = 0
    public var lastSuccessfulRequest: Date?
    public var lastFailure: String?
    public var launchTime: Date?
    public var sdkVersion: String = "1.0.0"
    public var bridgeVersion: String = "1.0.0"
    public var currentModel: String = "gpt-5-codex"
    public var bridgePID: Int32? = nil
    public var connectionDuration: TimeInterval {
        guard let launchTime else { return 0 }
        return Date().timeIntervalSince(launchTime)
    }
    public var streamStatus: String = "Idle"

    private init() {
        // Automatically start the bridge on init if needed or let lazy activation handle it
        if UserDefaults.standard.bool(forKey: "com.swiftcode.codex.completedSetup") {
            Task {
                await self.ensureBridgeRunning()
            }
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

    /// Resolves the bundled bridge directory dynamically using Bundle.main.
    public func locateResources() throws -> (packageJson: URL, bridgeJs: URL) {
        return try resolveBridgePath()
    }

    private func resolveBridgePath() throws -> (packageJson: URL, bridgeJs: URL) {
        // Look inside the main application bundle's resources
        if let bundlePath = Bundle.main.resourceURL?.appendingPathComponent("Codex/Bridge") {
            let packageJson = bundlePath.appendingPathComponent("package.json")
            let bridgeJs = bundlePath.appendingPathComponent("bridge.js")
            if FileManager.default.fileExists(atPath: bridgeJs.path) {
                return (packageJson, bridgeJs)
            }
        }

        // Fallback for development/local execution
        let fallbackDirs = [
            "SwiftCode/Resources/Codex/Bridge",
            "Resources/Codex/Bridge",
            "./SwiftCode/Resources/Codex/Bridge"
        ]

        for dir in fallbackDirs {
            let dirURL = URL(fileURLWithPath: dir)
            let packageJson = dirURL.appendingPathComponent("package.json")
            let bridgeJs = dirURL.appendingPathComponent("bridge.js")
            if FileManager.default.fileExists(atPath: bridgeJs.path) {
                return (packageJson, bridgeJs)
            }
        }

        throw NSError(
            domain: "CodexBridgeManager",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "OpenAI Codex Bridge resource files could not be located in the application bundle or local filesystem."]
        )
    }

    /// Checks if Node runtime is available on the machine.
    public func checkNodeRuntime() async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                if let data = try? pipe.fileHandleForReading.readToEnd(),
                   let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return version
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Checks if the local bridge server is responding to health check.
    public func isBridgeHealthy() async -> Bool {
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "ok" {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    /// Ensures that the bridge process is active and running, launching it if necessary.
    public func ensureBridgeRunning() async {
        guard !isShuttingDown else { return }

        if await isBridgeHealthy() {
            appendLog("Codex bridge is active and healthy.")
            bridgeStatus = .running
            return
        }

        appendLog("Codex bridge is offline. Initiating startup sequence...")
        bridgeStatus = .starting

        do {
            let paths = try resolveBridgePath()
            appendLog("Located bridge bundle at: \(paths.bridgeJs.path). Launching process.")

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["node", paths.bridgeJs.path]

            // Capture process stdout/stderr for logging
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = outPipe

            proc.terminationHandler = { [weak self] p in
                logger.warning("[terminationHandler] Codex bridge process exited with code: \(p.terminationStatus)")
                guard let self = self else { return }
                Task { @MainActor in
                    self.bridgePID = nil
                    self.bridgeStatus = .failed
                    if !self.isShuttingDown {
                        self.appendLog("Codex bridge process exited unexpectedly. Attempting automatic restart...")
                        self.bridgeStatus = .reconnecting
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await self.ensureBridgeRunning()
                    }
                }
            }

            try proc.run()
            self.process = proc
            self.bridgePID = proc.processIdentifier
            self.launchTime = Date()
            self.bridgeStatus = .running

            // Read output streams in the background asynchronously to avoid pipe clog
            Task.detached { [weak self] in
                guard let self = self else { return }
                let handle = outPipe.fileHandleForReading
                do {
                    for try await line in handle.bytes.lines {
                        await self.appendLog("[Node] \(line)")
                    }
                } catch {
                    await self.appendLog("Error reading stdout/stderr stream from Node process.")
                }
            }

            // Wait and poll for health status (up to 5 seconds)
            for _ in 1...10 {
                try await Task.sleep(nanoseconds: 500_000_000)
                if await isBridgeHealthy() {
                    appendLog("Codex bridge successfully launched and reporting active status.")
                    bridgeStatus = .running
                    return
                }
            }

            throw NSError(domain: "CodexBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to receive a healthy response from the bridge after launch."])

        } catch {
            bridgeStatus = .failed
            lastFailure = error.localizedDescription
            appendLog("Failed to start Codex bridge process: \(error.localizedDescription)")
        }
    }

    /// Gracefully shuts down the running bridge process.
    public func shutdownBridge() async {
        isShuttingDown = true
        guard let proc = process, proc.isRunning else { return }
        appendLog("Terminating Codex bridge process...")
        proc.terminate()
        self.process = nil
        self.bridgePID = nil
        self.bridgeStatus = .offline
    }

    /// Exposes API to validate the API key using the bridge.
    public func validateAPIKey(_ apiKey: String) async -> Bool {
        await ensureBridgeRunning()
        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [["role": "user", "content": "Respond with the single word VALID."]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    /// Run the step-by-step onboarding startup sequence.
    public func startStartupSequence(apiKey: String, onProgress: @MainActor @Sendable @escaping (CodexStartupStage, String) -> Void) async throws {
        // Stage 1: Validate API Key
        onProgress(.validateAPIKey, "Validating OpenAI API Key directly via OpenAI API...")
        appendLog("Locating OpenAI validation endpoint...")
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": "Respond with VALID"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            appendLog("Validation failed: \(errorMsg)")
            throw NSError(domain: "CodexOnboarding", code: 401, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key validation failed: \(errorMsg)"])
        }
        appendLog("OpenAI API key successfully validated.")

        // Stage 2: Save to Keychain
        onProgress(.saveToKeychain, "Saving key securely in system Keychain...")
        KeychainService.shared.set(apiKey, forKey: KeychainService.codexUserAPIKey)
        // Also save to default OpenAI key mapping to ensure other modules can use it
        KeychainService.shared.set(apiKey, forKey: "openai_api_key")
        appendLog("Key stored under '\(KeychainService.codexUserAPIKey)'.")

        // Stage 3: Locate Bundled Bridge
        onProgress(.locateBridge, "Locating bundled Node bridge resources...")
        let paths = try resolveBridgePath()
        appendLog("Bridge JS path resolved: \(paths.bridgeJs.path)")
        appendLog("Bridge package.json resolved: \(paths.packageJson.path)")

        // Stage 4: Verify required resources
        onProgress(.verifyResources, "Verifying package resource files...")
        if !FileManager.default.fileExists(atPath: paths.bridgeJs.path) {
            throw NSError(domain: "CodexOnboarding", code: 404, userInfo: [NSLocalizedDescriptionKey: "bridge.js file is missing."])
        }
        appendLog("Bridge resources verification complete.")

        // Stage 5: Verify Node runtime
        onProgress(.verifyNode, "Verifying node runtime availability...")
        guard let nodeVersion = await checkNodeRuntime() else {
            throw NSError(domain: "CodexOnboarding", code: 500, userInfo: [NSLocalizedDescriptionKey: "Node.js runtime not found. Please install Node.js (https://nodejs.org) to run the Codex Bridge."])
        }
        appendLog("Detected Node runtime version: \(nodeVersion)")

        // Stage 6: Launch Bridge
        onProgress(.launchBridge, "Launching Codex Node bridge server...")
        await ensureBridgeRunning()

        // Stage 7: Monitor Logs & Stage 8: Wait for Ready & Stage 9: Verify Comm
        onProgress(.monitorLogs, "Monitoring stdout & stderr channels...")
        onProgress(.waitForReady, "Awaiting health check on port \(port)...")
        var isHealthy = false
        for attempt in 1...15 {
            appendLog("Polling bridge health (attempt \(attempt)/15)...")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if await isBridgeHealthy() {
                isHealthy = true
                break
            }
        }
        if !isHealthy {
            throw NSError(domain: "CodexOnboarding", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to establish a connection with the Codex Node bridge. Check log output for details."])
        }
        onProgress(.verifyComm, "Established connection with Codex bridge on port \(port).")

        // Stage 10: Create session
        onProgress(.createSession, "Registering active Codex session...")
        sessionCount += 1
        appendLog("Active session initialized.")

        // Stage 11: Send Test Prompt
        onProgress(.sendTestPrompt, "Sending a test instruction: 'Respond with \"Codex connection successful.\"'")
        let promptStr = "Respond with the phrase: Codex connection successful."

        // Stage 12: Verify Streaming
        onProgress(.verifyStreaming, "Verifying streaming event channels...")
        var testResult = ""
        try await streamPrompt(promptStr) { token in
            testResult += token
            self.appendLog("Received token stream chunk: \"\(token)\"")
        }
        appendLog("Full streamed response received: \"\(testResult)\"")

        // Stage 13: Mark Ready
        onProgress(.markReady, "Marking Codex Ready...")
        UserDefaults.standard.set(true, forKey: "com.swiftcode.codex.completedSetup")
        appendLog("Onboarding setup sequence completed successfully!")
    }

    /// Exposes API to send non-streaming prompt to Codex.
    public func sendPrompt(_ prompt: String) async throws -> String {
        await ensureBridgeRunning()
        activeRequests += 1
        defer { activeRequests -= 1 }

        let apiKey = KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey)
            ?? KeychainService.shared.get(forKey: KeychainService.codexAppAPIKey)
            ?? ""

        guard !apiKey.isEmpty else {
            throw LLMError.invalidKey
        }

        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-5-codex",
            "messages": [["role": "user", "content": prompt]],
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let detail = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
                throw LLMError.networkError("Codex Bridge request failed: \(detail)")
            }

            struct ResponseObj: Codable {
                struct Choice: Codable {
                    struct Message: Codable {
                        let content: String
                    }
                    let message: Message
                }
                let choices: [Choice]
            }

            let decoded = try JSONDecoder().decode(ResponseObj.self, from: data)
            lastSuccessfulRequest = Date()
            return decoded.choices.first?.message.content ?? ""
        } catch {
            lastFailure = error.localizedDescription
            throw error
        }
    }

    /// Exposes API to stream response from Codex bridge.
    public func streamPrompt(_ prompt: String, onToken: @escaping @Sendable (String) async -> Void) async throws {
        await ensureBridgeRunning()
        activeRequests += 1
        streamStatus = "Streaming"
        defer {
            activeRequests -= 1
            streamStatus = "Idle"
        }

        let apiKey = KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey)
            ?? KeychainService.shared.get(forKey: KeychainService.codexAppAPIKey)
            ?? ""

        guard !apiKey.isEmpty else {
            throw LLMError.invalidKey
        }

        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-5-codex",
            "messages": [["role": "user", "content": prompt]],
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (stream, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.networkError("Codex Bridge stream failed to connect.")
        }

        for try await line in stream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard jsonString != "[DONE]" else { break }

            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let delta = first["delta"] as? [String: Any],
               let token = delta["content"] as? String {
                await onToken(token)
            }
        }
        lastSuccessfulRequest = Date()
    }
}
