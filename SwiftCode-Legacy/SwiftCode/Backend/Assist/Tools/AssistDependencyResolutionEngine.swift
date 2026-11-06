import Foundation

public struct AssistDependencyResolutionEngine: AssistTool {
    public let id = "dependency_resolution_engine"
    public let name = "Dependency Resolution Engine"
    public let description = "Resolves the workspace project's existing Swift Package dependencies via xcodebuild."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs xcodebuild -resolvePackageDependencies for the workspace project. NOTE: packageURL is a report label only — this tool does not add a new package dependency. Runs via an argument vector (never a shell string), bounded by a 300s timeout.",
            properties: [
                "packageURL": JSONSchema(type: "string", description: "Package URL label for the resolution report. The tool resolves the project's existing dependencies; it does not add this package.")
            ],
            required: ["packageURL"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let packageURL = input["packageURL"] as? String, !packageURL.isEmpty else {
            return .failure("Missing packageURL")
        }

        #if os(macOS)
        guard let located = AssistXcodeProjectResolver.locate(in: context.workspaceRoot) else {
            return .failure("No Xcode project (.xcodeproj/.xcworkspace) found in the workspace root; cannot resolve package dependencies.")
        }
        // Argument vector — never a shell string.
        let args = located.xcodebuildArgs + ["-resolvePackageDependencies"]
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
            return .failure("xcodebuild -resolvePackageDependencies timed out after 300s (killed).")
        }
        guard run.exitCode == 0 else {
            return .failure("Dependency resolution failed (exit code \(run.exitCode)): \(run.output.suffix(1500))")
        }
        return .success("Resolved dependencies for \(packageURL)", data: ["output": run.output, "package": packageURL, "exitCode": "\(run.exitCode)"])
        #else
        return .failure("Dependency resolution requires macOS runtime")
        #endif
    }
}
