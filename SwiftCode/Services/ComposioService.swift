import Foundation
import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "com.swiftcode.composio", category: "ComposioService")

// MARK: - Composio Connected Account Model

public struct ComposioConnectedAccount: Identifiable, Codable, Sendable, Hashable {
    public var id: String { wordId ?? "\(toolkit)_\(status)" }
    public let toolkit: String
    public let status: String
    public let wordId: String?

    public init(toolkit: String, status: String, wordId: String? = nil) {
        self.toolkit = toolkit
        self.status = status
        self.wordId = wordId
    }

    public var isActive: Bool {
        status.uppercased() == "ACTIVE"
    }

    public var systemIcon: String {
        switch toolkit.lowercased() {
        case "github": return "arrow.triangle.branch"
        case "slack": return "bubble.left.and.bubble.right.fill"
        case "googlecalendar", "calendar": return "calendar"
        case "gmail": return "envelope.fill"
        case "linear": return "checklist"
        case "jira": return "list.bullet.rectangle"
        case "notion": return "doc.text.fill"
        case "discord": return "message.fill"
        default: return "link.badge.plus"
        }
    }
}

// MARK: - Composio Execution Result

public struct ComposioExecutionResult: @unchecked Sendable {
    public let success: Bool
    public let output: String
    public let logId: String?
    public let duration: TimeInterval
    public let rawData: [String: Any]?

    public init(success: Bool, output: String, logId: String? = nil, duration: TimeInterval = 0, rawData: [String: Any]? = nil) {
        self.success = success
        self.output = output
        self.logId = logId
        self.duration = duration
        self.rawData = rawData
    }
}

// MARK: - Composio Service

@Observable
@MainActor
public final class ComposioService {
    public static let shared = ComposioService()

    public var isConnected: Bool = false
    public var apiKey: String = ""
    public var accountEmail: String = ""
    public var currentOrg: String = ""
    public var currentProject: String = ""
    public var testUserId: String = ""
    public var connectedAccounts: [ComposioConnectedAccount] = []
    public var isRefreshing: Bool = false
    public var isExecuting: Bool = false
    public var lastExecutionResult: String?
    public var lastLogId: String?
    public var lastLatency: TimeInterval = 0

    public var hasConfiguredKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let cliExecutableCandidates = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/composio").path,
        "/usr/local/bin/composio",
        "/opt/homebrew/bin/composio"
    ]

    private init() {
        loadCredentials()
        Task {
            await refreshStatus()
        }
    }

    // MARK: - Credential Management

    public func loadCredentials() {
        if let storedKey = KeychainService.shared.get(forKey: KeychainService.composioAPIKey), !storedKey.isEmpty {
            self.apiKey = storedKey
            return
        }

        // Check environment variable
        if let envKey = ProcessInfo.processInfo.environment["COMPOSIO_API_KEY"], !envKey.isEmpty {
            self.apiKey = envKey
            return
        }

        // Check ~/.composio/user_data.json
        let userDataURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".composio/user_data.json")
        if let data = try? Data(contentsOf: userDataURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let userApiKey = json["api_key"] as? String, !userApiKey.isEmpty {
            self.apiKey = userApiKey
            if let testUser = json["test_user_id"] as? String {
                self.testUserId = testUser
            }
        }
    }

    public func saveApiKey(_ newKey: String) {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = trimmed
        if trimmed.isEmpty {
            KeychainService.shared.delete(forKey: KeychainService.composioAPIKey)
        } else {
            KeychainService.shared.set(trimmed, forKey: KeychainService.composioAPIKey)
        }
        Task {
            await refreshStatus()
        }
    }

    // MARK: - CLI Path Resolution

    public var resolvedCLIPath: String? {
        for candidate in cliExecutableCandidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Refresh Status & Connected Accounts

    public func refreshStatus() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // 1. Try resolving whoami via CLI
        if let cliPath = resolvedCLIPath {
            let whoamiResult = await runProcess(executablePath: cliPath, arguments: ["whoami"])
            if whoamiResult.exitCode == 0 {
                parseWhoami(whoamiResult.stdout)
                self.isConnected = true
            }

            // 2. Fetch connected accounts via CLI
            let connResult = await runProcess(executablePath: cliPath, arguments: ["connections", "list"])
            if connResult.exitCode == 0, let data = connResult.stdout.data(using: .utf8) {
                parseConnectionsJSON(data)
            }
        } else if !apiKey.isEmpty {
            // Fallback: REST API validation
            await validateViaREST()
        } else {
            self.isConnected = false
        }
    }

    private func parseWhoami(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Email:") {
                let parts = trimmed.components(separatedBy: "Email:")
                if parts.count > 1 {
                    self.accountEmail = parts[1].trimmingCharacters(in: .whitespaces)
                }
            } else if trimmed.contains("Current Org:") {
                let parts = trimmed.components(separatedBy: "Current Org:")
                if parts.count > 1 {
                    self.currentOrg = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
    }

    private func parseConnectionsJSON(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] else {
            return
        }

        var accounts: [ComposioConnectedAccount] = []
        for (toolkit, list) in json {
            for item in list {
                let status = item["status"] as? String ?? "UNKNOWN"
                let wordId = item["word_id"] as? String
                accounts.append(ComposioConnectedAccount(toolkit: toolkit, status: status, wordId: wordId))
            }
        }
        self.connectedAccounts = accounts
        if !accounts.isEmpty {
            self.isConnected = true
        }
    }

    private func validateViaREST() async {
        guard let url = URL(string: "https://backend.composio.dev/api/v3.1/tools/execute/HACKERNEWS_GET_USER") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if apiKey.hasPrefix("uak_") {
            request.setValue(apiKey, forHTTPHeaderField: "x-user-api-key")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["arguments": ["username": "pg"]])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                self.isConnected = true
            } else {
                self.isConnected = false
            }
        } catch {
            self.isConnected = false
        }
    }

    // MARK: - Execute Tool

    public func executeTool(slug: String, argumentsJSON: String) async throws -> ComposioExecutionResult {
        isExecuting = true
        let startTime = Date()
        defer {
            isExecuting = false
            lastLatency = Date().timeIntervalSince(startTime)
        }

        let cleanArgs = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : argumentsJSON

        // Prefer CLI execution if installed
        if let cliPath = resolvedCLIPath {
            let result = await runProcess(executablePath: cliPath, arguments: ["execute", slug, "-d", cleanArgs])
            let duration = Date().timeIntervalSince(startTime)
            let combinedOutput = result.stdout.isEmpty ? result.stderr : result.stdout

            // Extract JSON from output
            var logId: String? = nil
            var isSuccess = result.exitCode == 0
            var responseData: [String: Any]? = nil

            if let openBrace = combinedOutput.firstIndex(of: "{"),
               let closeBrace = combinedOutput.lastIndex(of: "}") {
                let jsonSubstring = String(combinedOutput[openBrace...closeBrace])
                if let data = jsonSubstring.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    responseData = parsed
                    if let successVal = parsed["successful"] as? Bool {
                        isSuccess = successVal
                    }
                    logId = parsed["logId"] as? String ?? parsed["log_id"] as? String
                }
            }

            self.lastExecutionResult = combinedOutput
            self.lastLogId = logId

            return ComposioExecutionResult(
                success: isSuccess,
                output: combinedOutput,
                logId: logId,
                duration: duration,
                rawData: responseData
            )
        }

        // Fallback: Direct REST API execution
        guard let url = URL(string: "https://backend.composio.dev/api/v3.1/tools/execute/\(slug)") else {
            throw NSError(domain: "ComposioService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid tool slug URL."])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if apiKey.hasPrefix("uak_") {
            request.setValue(apiKey, forHTTPHeaderField: "x-user-api-key")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        let parsedArgs = (try? JSONSerialization.jsonObject(with: cleanArgs.data(using: .utf8) ?? Data())) as? [String: Any] ?? [:]
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["arguments": parsedArgs])

        let (data, response) = try await URLSession.shared.data(for: request)
        let duration = Date().timeIntervalSince(startTime)
        let outputString = String(data: data, encoding: .utf8) ?? "No response body"

        var isSuccess = false
        var logId: String? = nil
        var parsedJSON: [String: Any]? = nil

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parsedJSON = json
            isSuccess = json["successful"] as? Bool ?? ((response as? HTTPURLResponse)?.statusCode == 200)
            logId = json["logId"] as? String ?? json["log_id"] as? String
        }

        self.lastExecutionResult = outputString
        self.lastLogId = logId

        return ComposioExecutionResult(
            success: isSuccess,
            output: outputString,
            logId: logId,
            duration: duration,
            rawData: parsedJSON
        )
    }

    // MARK: - Generate Connect Link

    public func generateConnectLink(toolkit: String) async throws -> URL? {
        guard let cliPath = resolvedCLIPath else {
            throw NSError(domain: "ComposioService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Composio CLI is required to generate connect links."])
        }

        let result = await runProcess(executablePath: cliPath, arguments: ["link", toolkit, "--no-wait", "--no-browser"])
        let output = result.stdout

        // Scan for URL or parse JSON
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let redirectURLString = json["redirect_url"] as? String,
           let url = URL(string: redirectURLString) {
            return url
        }

        // Regex scan for connect link URL
        let pattern = #"https://connect\.composio\.dev/link/[a-zA-Z0-9_\-]+"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range, in: output) {
            let urlString = String(output[range])
            return URL(string: urlString)
        }

        return nil
    }

    // MARK: - Test Connection

    public func testConnection() async throws -> ComposioExecutionResult {
        // Run safe authenticated GitHub check or public Hackernews check
        if connectedAccounts.contains(where: { $0.toolkit.lowercased() == "github" && $0.isActive }) {
            return try await executeTool(slug: "GITHUB_GET_THE_AUTHENTICATED_USER", argumentsJSON: "{}")
        } else {
            return try await executeTool(slug: "HACKERNEWS_GET_USER", argumentsJSON: "{\"username\":\"pg\"}")
        }
    }

    // MARK: - Process Execution Helper

    private func runProcess(executablePath: String, arguments: [String]) async -> (stdout: String, stderr: String, exitCode: Int32) {
        let currentKey = self.apiKey
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments

                var env = ProcessInfo.processInfo.environment
                if let home = env["HOME"] {
                    env["PATH"] = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
                }
                if !currentKey.isEmpty {
                    env["COMPOSIO_API_KEY"] = currentKey
                }
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdout = String(data: outData, encoding: .utf8) ?? ""
                    let stderr = String(data: errData, encoding: .utf8) ?? ""

                    continuation.resume(returning: (stdout, stderr, process.terminationStatus))
                } catch {
                    continuation.resume(returning: ("", error.localizedDescription, -1))
                }
            }
        }
    }
}
