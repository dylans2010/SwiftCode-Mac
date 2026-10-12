import Foundation

// MARK: - Build Project (approval-exempt by design)
//
// This tool runs `xcodebuild` directly through `Process` — it deliberately
// does NOT route through the `use_terminal` tool, so it never triggers the
// terminal approval prompt. Building the user's project is the one terminal
// operation Assist may perform without user approval.
//
// It always targets the user's project (resolved from the workspace root),
// never SwiftCode's own bundle.

public struct AssistBuildProjectTool: AssistTool {
    public let id = "project_build"
    public let name = "Build Project"
    public let description = "Builds the user's Xcode project with xcodebuild, executed directly in the background without requiring terminal approval."
    public let capability: ToolCapability = .compilation
    public let riskLevel: ToolRiskLevel = .execution

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Builds the user's active Xcode project or workspace with xcodebuild. Runs in the background without a terminal approval prompt.",
            properties: [
                "projectPath": JSONSchema(type: "string", description: "Workspace-relative path to the .xcodeproj or .xcworkspace to build. Defaults to the project found in the workspace root."),
                "scheme": JSONSchema(type: "string", description: "The scheme to build. Defaults to the project's first listed scheme."),
                "configuration": JSONSchema(type: "string", description: "Build configuration (Debug or Release). Default is Debug."),
                "destination": JSONSchema(type: "string", description: "xcodebuild destination specifier. Default is 'platform=macOS'.")
            ],
            required: []
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let configuration: String = {
            if let c = input["configuration"] as? String, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c }
            return "Debug"
        }()
        let destination: String = {
            if let d = input["destination"] as? String, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return d }
            return "platform=macOS"
        }()
        let explicitScheme = input["scheme"] as? String

        #if os(macOS)
        let project: AssistXcodeProjectResolver.LocatedProject
        if let projectPath = input["projectPath"] as? String, !projectPath.isEmpty {
            guard let located = AssistXcodeProjectResolver.locate(relativePath: projectPath, in: context.workspaceRoot) else {
                return .failure("No .xcodeproj/.xcworkspace found at workspace-relative path '\(projectPath)'.")
            }
            project = located
        } else if let located = AssistXcodeProjectResolver.locate(in: context.workspaceRoot) {
            project = located
        } else {
            return .failure("No Xcode project (.xcodeproj/.xcworkspace) found in the workspace root. Open a project first or pass projectPath.")
        }

        let scheme = await AssistXcodeProjectResolver.resolveScheme(for: project, explicit: explicitScheme)

        let xcodebuildURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        guard FileManager.default.fileExists(atPath: xcodebuildURL.path) else {
            return .failure("xcodebuild not found at /usr/bin/xcodebuild. Install Xcode command line tools first.")
        }

        var env = ProcessInfo.processInfo.environment
        let arguments = project.xcodebuildArgs + [
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination,
            "build"
        ]

        await context.logger.info("Building user project '\(project.name)' (scheme: \(scheme), config: \(configuration)) via xcodebuild — approval-exempt", toolId: id)
        let startTime = Date()

        // Run in the background with live output streaming into the session log.
        let output = BuildOutputAccumulator()
        do {
            let succeeded = try await ProcessRunnerTool.shared.runStreamingAsync(
                executableURL: xcodebuildURL,
                arguments: arguments,
                environment: env,
                workingDirectory: context.workspaceRoot,
                onStdout: { chunk in
                    output.appendStdout(chunk)
                    Task { await context.logger.info(chunk.trimmingCharacters(in: .whitespacesAndNewlines), toolId: self.id) }
                },
                onStderr: { chunk in
                    output.appendStderr(chunk)
                }
            )
            let duration = Date().timeIntervalSince(startTime)
            let (stdoutAccum, stderrAccum) = output.snapshot()
            let combined = stdoutAccum + "\n" + stderrAccum
            let buildSucceeded = combined.contains("** BUILD SUCCEEDED **")
            let errors = parseBuildErrors(from: combined)
            let warnings = parseBuildWarnings(from: combined)
            let diagStrings = (errors + warnings).map { "\($0)" }
            let isSuccess = succeeded && buildSucceeded && errors.isEmpty

            let resultData: [String: String] = [
                "project": project.url.lastPathComponent,
                "scheme": scheme,
                "configuration": configuration,
                "status": isSuccess ? "Passed" : "Failed",
                "duration": String(format: "%.2fs", duration),
                "error_count": "\(errors.count)",
                "warning_count": "\(warnings.count)"
            ]

            if isSuccess {
                let tail = String(stdoutAccum.suffix(1500))
                return AssistToolResult(
                    success: true,
                    output: "Build Succeeded (\(String(format: "%.2fs", duration))) — \(project.name) / \(scheme) / \(configuration):\n\(tail)",
                    data: resultData,
                    diagnostics: diagStrings,
                    duration: duration,
                    exitCode: 0,
                    suggestedNextActions: ["project_test", "code_review"]
                )
            } else {
                let summary = errors.prefix(8).joined(separator: "\n")
                let detail = summary.isEmpty ? String(stderrAccum.suffix(1500)) : summary
                return AssistToolResult(
                    success: false,
                    output: "Build Failed (\(String(format: "%.2fs", duration))) — \(project.name) / \(scheme) / \(configuration), \(errors.count) error(s):\n\(detail)",
                    data: resultData,
                    error: errors.first ?? "xcodebuild did not report BUILD SUCCEEDED.",
                    errorCode: 1,
                    diagnostics: diagStrings,
                    duration: duration,
                    exitCode: 1,
                    suggestedNextActions: ["file_read", "code_replace", "diagnostic_inspect"]
                )
            }
        } catch {
            return .failure("xcodebuild execution failed: \(error.localizedDescription)")
        }
        #else
        return .failure("Project builds require the macOS runtime.")
        #endif
    }

    private func parseBuildErrors(from output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .filter { $0.contains(": error:") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func parseBuildWarnings(from output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .filter { $0.contains(": warning:") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Thread-safe accumulator for streamed process output.
private final class BuildOutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""

    func appendStdout(_ chunk: String) {
        lock.lock(); defer { lock.unlock() }
        stdout += chunk
    }

    func appendStderr(_ chunk: String) {
        lock.lock(); defer { lock.unlock() }
        stderr += chunk
    }

    func snapshot() -> (String, String) {
        lock.lock(); defer { lock.unlock() }
        return (stdout, stderr)
    }
}

// MARK: - Generate Xcode Project (xcodegen, approval-exempt by design)
//
// Generates `.xcodeproj` bundles from an XcodeGen `project.yml` spec, running
// `xcodegen` directly through `Process` (never via `use_terminal`, so no
// approval prompt). If XcodeGen is not installed, it is installed for the
// user with Homebrew — also without an approval prompt, per explicit user
// configuration.

public struct AssistGenerateXcodeprojTool: AssistTool {
    public let id = "generate_xcodeproj"
    public let name = "Generate Xcode Project"
    public let description = "Generates .xcodeproj files from an XcodeGen project.yml spec. Installs XcodeGen automatically if missing. Runs in the background without a terminal approval prompt."
    public let capability: ToolCapability = .compilation
    public let riskLevel: ToolRiskLevel = .execution

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs xcodegen to generate .xcodeproj files from a project.yml spec in the user's workspace. Installs xcodegen via Homebrew when absent.",
            properties: [
                "spec": JSONSchema(type: "string", description: "Workspace-relative path to the XcodeGen spec file. Default is 'project.yml'."),
                "useCache": JSONSchema(type: "string", description: "'true' to pass --use-cache to xcodegen. Default is 'false'.")
            ],
            required: []
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        #if os(macOS)
        let spec: String = {
            if let s = input["spec"] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            return "project.yml"
        }()
        let useCache = ((input["useCache"] as? String)?.lowercased() == "true")
        let specURL = context.workspaceRoot.appendingPathComponent(spec)
        guard FileManager.default.fileExists(atPath: specURL.path) else {
            return .failure("XcodeGen spec not found at '\(spec)' (resolved to \(specURL.path)). Create a project.yml first or pass the spec parameter.")
        }

        let startTime = Date()

        // 1. Ensure xcodegen is available, installing it when missing.
        let xcodegenURL: URL
        do {
            xcodegenURL = try await ensureXcodegen(context: context)
        } catch {
            return .failure(error.localizedDescription)
        }

        // 2. Run xcodegen generate in the background.
        var arguments = ["generate", "--spec", specURL.path]
        if useCache { arguments.append("--use-cache") }

        await context.logger.info("Generating Xcode project from \(spec) via xcodegen — approval-exempt", toolId: id)
        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: xcodegenURL,
                arguments: arguments,
                workingDirectory: context.workspaceRoot
            )
            let duration = Date().timeIntervalSince(startTime)
            let combined = res.stdout + "\n" + res.stderr

            // 3. Verify a .xcodeproj was actually produced.
            let produced = findGeneratedProjects(in: context.workspaceRoot)

            if res.exitCode == 0, !produced.isEmpty {
                return AssistToolResult(
                    success: true,
                    output: "XcodeGen succeeded (\(String(format: "%.2fs", duration))). Generated: \(produced.joined(separator: ", "))\n\(res.stdout.suffix(1200))",
                    data: ["spec": spec, "projects": produced.joined(separator: ","),
                           "duration": String(format: "%.2fs", duration)],
                    duration: duration,
                    exitCode: 0,
                    suggestedNextActions: ["project_build"]
                )
            } else {
                return AssistToolResult(
                    success: false,
                    output: "XcodeGen failed (exit \(res.exitCode), \(String(format: "%.2fs", duration))):\n\(combined.suffix(1500))",
                    data: ["spec": spec, "duration": String(format: "%.2fs", duration)],
                    error: "xcodegen exited with code \(res.exitCode)",
                    errorCode: Int(res.exitCode),
                    duration: duration,
                    exitCode: res.exitCode,
                    suggestedNextActions: ["file_read"]
                )
            }
        } catch {
            return .failure("xcodegen execution failed: \(error.localizedDescription)")
        }
        #else
        return .failure("Xcode project generation requires the macOS runtime.")
        #endif
    }

    #if os(macOS)
    /// Returns a usable xcodegen binary, installing it via Homebrew when absent.
    /// Installation runs without a user approval prompt by explicit configuration.
    private func ensureXcodegen(context: AssistContext) async throws -> URL {
        let candidates = [
            "/opt/homebrew/bin/xcodegen",
            "/usr/local/bin/xcodegen",
            "/opt/homebrew/opt/xcodegen/bin/xcodegen"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // Fall back to PATH lookup.
        let which = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/which"),
            arguments: ["xcodegen"]
        )
        let found = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if which.exitCode == 0, !found.isEmpty, FileManager.default.fileExists(atPath: found) {
            return URL(fileURLWithPath: found)
        }

        // Not installed — install via Homebrew without prompting.
        await context.logger.info("xcodegen not found; installing via Homebrew (no approval prompt by configuration)", toolId: id)
        let brewURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        let brewFallback = URL(fileURLWithPath: "/usr/local/bin/brew")
        let brew: URL
        if FileManager.default.fileExists(atPath: brewURL.path) {
            brew = brewURL
        } else if FileManager.default.fileExists(atPath: brewFallback.path) {
            brew = brewFallback
        } else {
            throw NSError(
                domain: "AssistGenerateXcodeprojTool", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "xcodegen is not installed and Homebrew was not found. Install Homebrew (https://brew.sh), then run this tool again — it will install xcodegen automatically."]
            )
        }
        let install = try await ProcessRunnerTool.shared.run(
            executableURL: brew,
            arguments: ["install", "xcodegen"]
        )
        guard install.exitCode == 0 else {
            throw NSError(
                domain: "AssistGenerateXcodeprojTool", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Automatic xcodegen installation failed (brew exit \(install.exitCode)): \(install.stderr.suffix(500)). Install it manually with 'brew install xcodegen'."]
            )
        }
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw NSError(
            domain: "AssistGenerateXcodeprojTool", code: 4,
            userInfo: [NSLocalizedDescriptionKey: "brew reported success but no xcodegen binary was found afterwards."]
        )
    }

    private func findGeneratedProjects(in workspaceRoot: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
            .filter { $0.pathExtension == "xcodeproj" }
            .map { $0.lastPathComponent }
            .sorted() ?? []
    }
    #endif
}
