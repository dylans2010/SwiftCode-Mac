//
//  MuseCodeCLIHelper.swift
//  SwiftCode
//
//  Provides executable discovery, installation, credential checks, and asynchronous
//  process execution helper for the "Assist with Meta" CLI (muse).
//

import Foundation

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
            "/usr/local/bin/muse",
            "/opt/homebrew/bin/muse",
            NSString(string: "~/.nvm/versions/node/current/bin/muse").expandingTildeInPath,
            NSString(string: "~/.muse/bin/muse").expandingTildeInPath,
            NSString(string: "~/.local/bin/muse").expandingTildeInPath,
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
            if let path = env["PATH"] {
                env["PATH"] = path + ":/opt/homebrew/bin:/usr/local/bin"
            } else {
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            }
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

    /// Checks if valid account credentials exist.
    public func checkCredentials() async -> Bool {
        guard isInstalled() else { return false }
        do {
            let result = try await runCommand(args: ["account", "read"])
            return result.isSuccess && !result.stdout.contains("unauthenticated")
        } catch {
            return false
        }
    }
}
