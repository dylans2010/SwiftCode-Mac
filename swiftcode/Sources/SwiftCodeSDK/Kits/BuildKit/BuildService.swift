import Foundation
import SwiftCodeSubprocess

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

/// Thin adapter over the SwiftCode build seam.
///
/// Legacy's `BuildService` never drove `xcodebuild`: it ran `swift build`
/// for Swift packages, `npm run build` (or `node`) for extensions, and fell
/// back to `swift build` for anything else. This port keeps exactly that
/// strategy, executed through `SwiftCodeSubprocess` instead of raw `Process`.
/// Xcode-project builds belong to `SwiftCodeBuild` / `SwiftCodeXcodebuild` — the
/// `build.execute` IPC method (see `SDKBuildContracts`) must be routed
/// there by the host dispatcher, not to this service.
public final class BuildService: Sendable {
    private let toolchain: Toolchain

    public init(toolchain: Toolchain = .standard) {
        self.toolchain = toolchain
    }

    public func build(config: BuildConfig) async throws -> BuildResult {
        let startTime = Date()
        let ws = Workspace(path: config.projectPath)

        // Determine build strategy based on files in project.
        let executable: String
        var args: [String] = []

        if ws.fileAccess.exists(at: "swiftcode.json") {
            // Extension: use npm run build or tsc if present.
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
            // Default to swiftc or xcodebuild.
            guard let swift = toolchain.resolveExecutable(name: "swift") else {
                throw WorkspaceError.readFailed(config.projectPath, "No supported build system detected")
            }
            executable = swift
            args = ["build", "-c", config.configuration.rawValue]
        }

        args.append(contentsOf: config.additionalArguments)

        var env = ProcessInfo.processInfo.environment
        for (k, v) in config.environmentVariables {
            env[k] = v
        }

        let output = try Subprocess.run(
            executable,
            args,
            environment: env,
            currentDirectory: URL(fileURLWithPath: ws.root.normalizedPath)
        )
        let stdout = output.stdoutText
        let stderr = output.stderrText
        let duration = Date().timeIntervalSince(startTime)

        let parser = BuildDiagnosticsParser()
        let diags = parser.parse(output: stdout + "\n" + stderr)
        let succeeded = (output.status == 0)

        return BuildResult(
            exitCode: output.status,
            stdout: stdout,
            stderr: stderr,
            duration: duration,
            diagnostics: diags,
            succeeded: succeeded
        )
    }
}
