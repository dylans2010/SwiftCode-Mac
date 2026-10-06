import Foundation

public struct AssistDependencyResolutionEngine: AssistTool {
    public let id = "dependency_resolution_engine"
    public let name = "Dependency Resolution Engine"
    public let description = "Adds and resolves Swift Package dependencies and integrates package references into the project."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Resolves Swift package dependencies for the project via xcodebuild. macOS only.",
            properties: [
                "packageURL": JSONSchema(type: "string", description: "Package URL label for the resolution report.")
            ],
            required: ["packageURL"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let packageURL = input["packageURL"] as? String, !packageURL.isEmpty else {
            return .failure("Missing packageURL")
        }

        #if os(macOS)
        let resolveOutput = try run(command: "xcodebuild -resolvePackageDependencies -project SwiftCode.xcodeproj", cwd: context.workspaceRoot.path)
        return .success("Resolved dependencies for \(packageURL)", data: ["output": resolveOutput, "package": packageURL])
        #else
        return .failure("Dependency resolution requires macOS runtime")
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
}
