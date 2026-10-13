import Foundation
import DiagnosticsKit
import WorkspaceKit

public struct BuildResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let duration: TimeInterval
    public let diagnostics: [Diagnostic]
    public let succeeded: Bool

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        duration: TimeInterval,
        diagnostics: [Diagnostic],
        succeeded: Bool
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
        self.diagnostics = diagnostics
        self.succeeded = succeeded
    }
}

public final class BuildService: Sendable {
    private let toolchain: Toolchain

    public init(toolchain: Toolchain = .standard) {
        self.toolchain = toolchain
    }

    public func build(config: BuildConfig) async throws -> BuildResult {
        let startTime = Date()
        let ws = Workspace(path: config.projectPath)

        // Determine build strategy based on files in project
        let executable: String
        var args: [String] = []

        if ws.fileAccess.exists(at: "swiftcode.json") {
            // Extension: use npm run build or tsc if present
            if let npm = toolchain.resolveExecutable(name: "npm") {
                executable = npm
                args = ["run", "build"]
            } else if let node = toolchain.resolveExecutable(name: "node") {
                executable = node
                args = ["dist/index.js"]
            } else {
                throw WorkspaceError.readFailed(config.projectPath, "No node/npm runtime available for building extension")
            }
        } else if ws.fileAccess.exists(at: "Package.swift") {
            guard let swift = toolchain.resolveExecutable(name: "swift") else {
                throw WorkspaceError.readFailed(config.projectPath, "Swift toolchain not found")
            }
            executable = swift
            args = ["build", "--package-path", ws.root.normalizedPath, "-c", config.configuration.rawValue, "--disable-sandbox"]
            if let target = config.target {
                args.append(contentsOf: ["--target", target])
            }
        } else {
            // Default to swiftc or xcodebuild
            guard let swift = toolchain.resolveExecutable(name: "swift") else {
                throw WorkspaceError.readFailed(config.projectPath, "No supported build system detected")
            }
            executable = swift
            args = ["build", "-c", config.configuration.rawValue]
        }

        args.append(contentsOf: config.additionalArguments)

        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: ws.root.normalizedPath)
        process.standardOutput = outPipe
        process.standardError = errPipe

        var env = ProcessInfo.processInfo.environment
        for (k, v) in config.environmentVariables {
            env[k] = v
        }
        process.environment = env

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        let duration = Date().timeIntervalSince(startTime)

        let parser = BuildDiagnosticsParser()
        let diags = parser.parse(output: stdout + "\n" + stderr)
        let succeeded = (process.terminationStatus == 0)

        return BuildResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            duration: duration,
            diagnostics: diags,
            succeeded: succeeded
        )
    }
}
