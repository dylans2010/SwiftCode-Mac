import Foundation

public struct AssistCompilerDiagnosticsEngine: AssistTool {
    public let id = "compiler_diagnostics_engine"
    public let name = "Compiler Diagnostics Engine"
    public let description = "Runs xcodebuild and parses warnings/errors into structured diagnostics."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs a full xcodebuild build and parses warnings and errors into structured diagnostics. macOS only. Targets the user's project. Runs via an argument vector (never a shell string), bounded by a 300s timeout.",
            properties: [
                "project": JSONSchema(type: "string", description: "Workspace-relative path to the .xcodeproj/.xcworkspace to diagnose. Defaults to the project found in the workspace root."),
                "scheme": JSONSchema(type: "string", description: "Build scheme. Defaults to the project's first listed scheme.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        #if os(macOS)
        let located: AssistXcodeProjectResolver.LocatedProject
        if let projectPath = input["project"] as? String, !projectPath.isEmpty,
           let found = AssistXcodeProjectResolver.locate(relativePath: projectPath, in: context.workspaceRoot) {
            located = found
        } else if let found = AssistXcodeProjectResolver.locate(in: context.workspaceRoot) {
            located = found
        } else {
            return .failure("No Xcode project (.xcodeproj/.xcworkspace) found in the workspace root.")
        }
        let scheme = await AssistXcodeProjectResolver.resolveScheme(for: located, explicit: input["scheme"] as? String)
        // Argument vector — never a shell string: a crafted scheme name is an
        // inert argument here, not executable shell.
        let args = located.xcodebuildArgs + ["-scheme", scheme, "-configuration", "Debug", "build"]
        let run: AssistArgvRunner.Result
        do {
            run = try AssistArgvRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: args,
                workingDirectory: context.workspaceRoot,
                timeout: 300
            )
        } catch {
            return .failure("Failed to run xcodebuild: \(error.localizedDescription)")
        }
        if run.timedOut {
            return .failure("xcodebuild timed out after 300s (killed). No diagnostics collected.")
        }
        var diagnostics = parseDiagnostics(run.output)
        diagnostics["exitCode"] = "\(run.exitCode)"
        diagnostics["buildFailed"] = run.exitCode == 0 ? "false" : "true"
        // Success means "diagnostics were collected", not "the build passed":
        // the build failure is explicit in the output and in the data.
        let headline = run.exitCode == 0
            ? "Compiler diagnostics collected (build succeeded)."
            : "Compiler diagnostics collected (build FAILED, exit code \(run.exitCode))."
        return .success(headline, data: diagnostics)
        #else
        return .failure("Compiler diagnostics are only available on macOS runtime")
        #endif
    }

    private func parseDiagnostics(_ output: String) -> [String: String] {
        let lines = output.components(separatedBy: .newlines)
        let errors = lines.filter { $0.contains(": error:") }
        let warnings = lines.filter { $0.contains(": warning:") }
        return [
            "error_count": "\(errors.count)",
            "warning_count": "\(warnings.count)",
            "errors": errors.prefix(200).joined(separator: "\n"),
            "warnings": warnings.prefix(200).joined(separator: "\n")
        ]
    }
}
