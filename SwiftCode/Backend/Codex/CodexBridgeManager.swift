import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.CodexBridge", category: "CodexBridgeManager")

@MainActor
public final class CodexBridgeManager: Sendable {
    public static let shared = CodexBridgeManager()

    private let port = 3003
    private let healthURL = URL(string: "http://127.0.0.1:3003/health")!
    private let completionsURL = URL(string: "http://127.0.0.1:3003/v1/chat/completions")!

    // Mutable state needs isolation or a helper. Since this is @MainActor, it is perfectly safe to manage mutable non-Sendable properties.
    private var process: Process?
    private var isShuttingDown = false

    private init() {
        // Automatically start the bridge on init if needed or let lazy activation handle it
        Task {
            await self.ensureBridgeRunning()
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

    /// Resolves the bundled bridge directory dynamically using Bundle.main.
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
            logger.log("[ensureBridgeRunning] Codex bridge is active and healthy.")
            return
        }

        logger.log("[ensureBridgeRunning] Codex bridge is offline. Initiating startup sequence...")

        do {
            let paths = try resolveBridgePath()
            logger.log("[ensureBridgeRunning] Located bridge bundle at: \(paths.bridgeJs.path). Launching process.")

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
                    if !self.isShuttingDown {
                        logger.log("[terminationHandler] Attempting automatic restart...")
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await self.ensureBridgeRunning()
                    }
                }
            }

            try proc.run()
            self.process = proc

            // Read output streams in the background asynchronously to avoid pipe clog
            Task.detached {
                let handle = outPipe.fileHandleForReading
                for try await line in handle.bytes.lines {
                    logger.log("[Node stdout] \(line)")
                }
            }

            // Wait and poll for health status (up to 5 seconds)
            for _ in 1...10 {
                try await Task.sleep(nanoseconds: 500_000_000)
                if await isBridgeHealthy() {
                    logger.log("[ensureBridgeRunning] Codex bridge successfully launched and reporting active status.")
                    return
                }
            }

            throw NSError(domain: "CodexBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to receive a healthy response from the bridge after launch."])

        } catch {
            logger.error("[ensureBridgeRunning] Failed to start Codex bridge process: \(error.localizedDescription)")
        }
    }

    /// Gracefully shuts down the running bridge process.
    public func shutdownBridge() async {
        isShuttingDown = true
        guard let proc = process, proc.isRunning else { return }
        logger.log("[shutdownBridge] Terminating Codex bridge process...")
        proc.terminate()
        self.process = nil
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

    /// Exposes API to send non-streaming prompt to Codex.
    public func sendPrompt(_ prompt: String) async throws -> String {
        await ensureBridgeRunning()

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
        return decoded.choices.first?.message.content ?? ""
    }

    /// Exposes API to stream response from Codex bridge.
    public func streamPrompt(_ prompt: String, onToken: @escaping @Sendable (String) async -> Void) async throws {
        await ensureBridgeRunning()

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
    }
}
