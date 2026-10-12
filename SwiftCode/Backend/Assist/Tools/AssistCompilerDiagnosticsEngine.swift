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
            description: "Runs xcodebuild and parses warnings and errors into structured diagnostics. macOS only. Targets the user's project.",
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
        let cmd = "xcodebuild \(located.xcodebuildArgs.joined(separator: " ")) -scheme \(scheme) -configuration Debug build"
        let output = try run(command: cmd, cwd: context.workspaceRoot.path)
        let diagnostics = parseDiagnostics(output)
        return .success("Compiler diagnostics collected.", data: diagnostics)
        #else
        return .failure("Compiler diagnostics are only available on macOS runtime")
        #endif
    }

    #if os(macOS)
    private func run(command: String, cwd: String) throws -> String {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", command]
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    #endif

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
