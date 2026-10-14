//
//  MuseCodeCLIHelper.swift
//  SwiftCode
//
//  Provides executable discovery, installation, credential checks, and asynchronous
//  process execution helper for the "Assist with Meta" CLI (muse).
//

import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Muse Auth Config JSON Model

public struct MuseAuthConfigFile: Codable, Sendable {
    public let schemaVersion: Int?
    public let providers: [String: MuseAuthProviderConfig]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case providers
    }
}

public struct MuseAuthProviderConfig: Codable, Sendable {
    public let mechanism: String?
    public let storage: String?
    public let obtainedVia: String?
    public let apiBaseUrl: String?
    public let subsActive: Bool?
    public let userFullName: String?
    public let userEmail: String?
    public let accessToken: String?
    public let apiKey: String?

    enum CodingKeys: String, CodingKey {
        case mechanism
        case storage
        case obtainedVia = "obtained_via"
        case apiBaseUrl = "api_base_url"
        case subsActive = "subs_active"
        case userFullName = "user_full_name"
        case userEmail = "user_email"
        case accessToken = "access_token"
        case apiKey = "api_key"
    }
}

public struct MuseCodeCLIExecutionResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool {
        return exitCode == 0
    }
}

public enum MuseCodeCLIError: Error, LocalizedError {
    case executableNotFound
    case installationFailed(String)
    case executionFailed(exitCode: Int32, stderr: String)
    case timeout
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "The 'muse' CLI executable was not found on your system."
        case .installationFailed(let msg):
            return "Failed to install 'muse' CLI: \(msg)"
        case .executionFailed(let code, let stderr):
            return "CLI execution failed with code \(code): \(stderr)"
        case .timeout:
            return "CLI command timed out."
        case .cancelled:
            return "CLI operation was cancelled."
        }
    }
}

public actor MuseCodeCLIHelper {
    public static let shared = MuseCodeCLIHelper()

    private init() {}

    /// Discovers the path to the `muse` executable.
    nonisolated public func discoverExecutablePath() -> String? {
        let fileManager = FileManager.default

        // Standard paths
        let candidatePaths = [
            NSString(string: "~/.local/bin/muse").expandingTildeInPath,
            "/usr/local/bin/muse",
            "/opt/homebrew/bin/muse",
            NSString(string: "~/.nvm/versions/node/current/bin/muse").expandingTildeInPath,
            NSString(string: "~/.muse/bin/muse").expandingTildeInPath,
            "/usr/bin/muse"
        ]

        for path in candidatePaths {
            if fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Search PATH environment variable
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        let paths = envPath.split(separator: ":").map(String.init)
        for dir in paths {
            let fullPath = (dir as NSString).appendingPathComponent("muse")
            if fileManager.fileExists(atPath: fullPath) && fileManager.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }

    /// Checks whether the `muse` CLI is available.
    nonisolated public func isInstalled() -> Bool {
        return discoverExecutablePath() != nil
    }

    /// Locates the auth credentials JSON configuration file.
    nonisolated public func getAuthFilePath() -> String? {
        let fileManager = FileManager.default
        if let envPath = ProcessInfo.processInfo.environment["MUSE_AUTH_PATH"],
           fileManager.fileExists(atPath: envPath) {
            return envPath
        }
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            let p = (xdg as NSString).appendingPathComponent("muse/auth.json")
            if fileManager.fileExists(atPath: p) { return p }
        }
        let home = NSHomeDirectory()
        let standardPath = (home as NSString).appendingPathComponent(".config/muse/auth.json")
        if fileManager.fileExists(atPath: standardPath) {
            return standardPath
        }
        let altPath = (home as NSString).appendingPathComponent(".muse/auth.json")
        if fileManager.fileExists(atPath: altPath) {
            return altPath
        }
        return standardPath
    }

    /// Reads authentication metadata from the credentials configuration file.
    nonisolated public func readAuthInfo() -> (isAuthenticated: Bool, email: String?, fullName: String?) {
        guard let path = getAuthFilePath() else {
            return (false, nil, nil)
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return (false, nil, nil)
        }
        if let config = try? JSONDecoder().decode(MuseAuthConfigFile.self, from: data),
           let meta = config.providers?["meta"] {
            let email = meta.userEmail
            let name = meta.userFullName
            let hasCreds = (email != nil && !email!.isEmpty) ||
                           (meta.accessToken != nil && !meta.accessToken!.isEmpty) ||
                           (meta.apiKey != nil && !meta.apiKey!.isEmpty) ||
                           (meta.mechanism != nil && !meta.mechanism!.isEmpty)
            return (hasCreds, email, name)
        }
        // Fallback generic extraction if structure varies
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let providers = json["providers"] as? [String: Any],
           let meta = providers["meta"] as? [String: Any] {
            let email = meta["user_email"] as? String
            let name = meta["user_full_name"] as? String
            let hasCreds = email != nil || meta["access_token"] != nil || meta["mechanism"] != nil
            return (hasCreds, email, name)
        }
        return (false, nil, nil)
    }

    /// Checks if valid account credentials exist.
    public func checkCredentials() async -> Bool {
        guard isInstalled() else { return false }
        return readAuthInfo().isAuthenticated
    }

    /// Retrieves the authenticated email address if available.
    public func getUserEmail() async -> String? {
        return readAuthInfo().email
    }

    /// Runs a `muse` command asynchronously using `Process`.
    public func runCommand(args: [String], environment: [String: String]? = nil, timeoutSeconds: Double = 30.0) async throws -> MuseCodeCLIExecutionResult {
        guard let executable = discoverExecutablePath() else {
            throw MuseCodeCLIError.executableNotFound
        }

        return try await runProcess(executablePath: executable, args: args, environment: environment, timeoutSeconds: timeoutSeconds)
    }

    /// Reusable helper to run a process.
    public func runProcess(executablePath: String, args: [String], environment: [String: String]? = nil, timeoutSeconds: Double = 30.0) async throws -> MuseCodeCLIExecutionResult {
        return try await Task.detached { () -> MuseCodeCLIExecutionResult in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = args

            var env = ProcessInfo.processInfo.environment
            if let customEnv = environment {
                for (k, v) in customEnv {
                    env[k] = v
                }
            }
            // Ensure PATH is comprehensive for GUI mac apps
            let home = NSHomeDirectory()
            let localBin = (home as NSString).appendingPathComponent(".local/bin")
            let museBin = (home as NSString).appendingPathComponent(".muse/bin")
            let existingPath = env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = "\(localBin):\(museBin):/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            process.waitUntilExit()

            let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

            return MuseCodeCLIExecutionResult(
                exitCode: process.terminationStatus,
                stdout: stdoutStr.trimmingCharacters(in: .whitespacesAndNewlines),
                stderr: stderrStr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.value
    }

    /// Runs the CLI login flow (`muse login`) using `Process`.
    /// Emits authentication URL/code via callback, waits for login approval, and returns the authenticated email.
    public func runLoginFlow(onAuthURL: (@Sendable (URL, String?) -> Void)? = nil) async throws -> String {
        guard let executable = discoverExecutablePath() else {
            throw MuseCodeCLIError.executableNotFound
        }

        return try await Task.detached { () -> String in
            final class LoginProcessState: @unchecked Sendable {
                private let lock = NSLock()
                private var output = ""
                private var opened = false

                func appendAndExtractURL(_ data: Data) -> (url: URL, code: String?)? {
                    guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
                    lock.lock()
                    defer { lock.unlock() }
                    output += text
                    if !opened, let match = output.range(of: #"https://auth\.meta\.com[^\s\n\"']+"#, options: .regularExpression) {
                        opened = true
                        let urlStr = String(output[match])
                        if let url = URL(string: urlStr) {
                            var code: String? = nil
                            if let codeRange = urlStr.range(of: #"code=([A-Z0-9-]+)"#, options: .regularExpression) {
                                code = String(urlStr[codeRange]).replacingOccurrences(of: "code=", with: "")
                            }
                            return (url, code)
                        }
                    }
                    return nil
                }

                var combinedOutput: String {
                    lock.lock()
                    defer { lock.unlock() }
                    return output
                }
            }

            let state = LoginProcessState()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["login"]

            var env = ProcessInfo.processInfo.environment
            let home = NSHomeDirectory()
            let localBin = (home as NSString).appendingPathComponent(".local/bin")
            let museBin = (home as NSString).appendingPathComponent(".muse/bin")
            let existingPath = env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = "\(localBin):\(museBin):/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let handleData: @Sendable (Data) -> Void = { data in
                if let extracted = state.appendAndExtractURL(data) {
                    onAuthURL?(extracted.url, extracted.code)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                guard !d.isEmpty else { return }
                handleData(d)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                guard !d.isEmpty else { return }
                handleData(d)
            }

            try process.run()
            process.waitUntilExit()

            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutPipe.fileHandleForReading.readabilityHandler = nil

            let remainingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let remainingErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            handleData(remainingOut)
            handleData(remainingErr)

            // Re-read auth info after process exit
            let info = MuseCodeCLIHelper.shared.readAuthInfo()
            if let email = info.email, !email.isEmpty {
                return email
            }
            if process.terminationStatus == 0 {
                return info.email ?? "Authenticated"
            }
            let errOutput = state.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MuseCodeCLIError.executionFailed(
                exitCode: process.terminationStatus,
                stderr: errOutput.isEmpty
                    ? "Authentication process exited with status \(process.terminationStatus)."
                    : errOutput
            )
        }.value
    }

    /// Attempts to install `muse` CLI globally via npm if missing.
    public func installCLIViaNPM() async throws {
        // Find npm executable
        let fileManager = FileManager.default
        let npmCandidates = [
            "/opt/homebrew/bin/npm",
            "/usr/local/bin/npm",
            NSString(string: "~/.nvm/versions/node/current/bin/npm").expandingTildeInPath,
            "/usr/bin/npm"
        ]

        guard let npmPath = npmCandidates.first(where: { fileManager.fileExists(atPath: $0) && fileManager.isExecutableFile(atPath: $0) }) else {
            throw MuseCodeCLIError.installationFailed("npm package manager was not found. Please install Node.js and npm.")
        }

        let result = try await runProcess(executablePath: npmPath, args: ["install", "-g", "@muse-code/sdk"], timeoutSeconds: 120.0)
        if !result.isSuccess {
            throw MuseCodeCLIError.installationFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}

// MARK: - Meta Account Auth Service

@MainActor
public final class MetaAccountAuthService: ObservableObject {
    public static let shared = MetaAccountAuthService()

    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var userEmail: String? = nil
    @Published public private(set) var userFullName: String? = nil
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public private(set) var authError: String? = nil
    @Published public private(set) var currentAuthURL: URL? = nil
    @Published public private(set) var currentCode: String? = nil

    private init() {
        checkAuthStatus()
    }

    public func checkAuthStatus() {
        let info = MuseCodeCLIHelper.shared.readAuthInfo()
        self.isAuthenticated = info.isAuthenticated
        self.userEmail = info.email
        self.userFullName = info.fullName
        if info.isAuthenticated {
            self.authError = nil
        }
    }

    public func onAssistOnMetaSelected() {
        checkAuthStatus()
        if !isAuthenticated || userEmail == nil {
            startAuthFlow()
        }
    }

    public func startAuthFlow() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil
        currentAuthURL = nil
        currentCode = nil

        Task {
            do {
                let email = try await MuseCodeCLIHelper.shared.runLoginFlow { [weak self] url, code in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.currentAuthURL = url
                        self.currentCode = code
                        #if canImport(AppKit)
                        NSWorkspace.shared.open(url)
                        #endif
                    }
                }
                await MainActor.run {
                    self.isAuthenticating = false
                    self.isAuthenticated = true
                    self.userEmail = email
                    self.authError = nil
                    Task {
                        _ = await MetaAssistProvider.shared.discoverModels()
                        _ = await AssistModelDiscoveryService.shared.discoverAllModels(forceRefresh: true)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.checkAuthStatus()
                    if !self.isAuthenticated {
                        self.authError = error.localizedDescription
                    }
                }
            }
        }
    }
}

