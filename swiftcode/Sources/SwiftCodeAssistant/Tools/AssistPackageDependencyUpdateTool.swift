import Foundation

public struct AssistPackageDependencyUpdateTool: AssistTool {
    public let id = "package_dependency_update"
    public let name = "Update Package Dependencies"
    public let description = "Runs swift package update in the workspace root to update Swift package dependencies."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Updates Swift package dependencies.",
            properties: [
                "package": JSONSchema(type: "string", description: "Optional single dependency name to update. When omitted, all dependencies are updated.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let swiftPath = "/usr/bin/swift"
        guard FileManager.default.fileExists(atPath: swiftPath) else {
            return .failure("Swift not found at /usr/bin/swift.")
        }
        let manifestURL = context.workspaceRoot.standardizedFileURL.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .failure("Package.swift not found in the workspace root.")
        }
        var args = ["package", "update"]
        if let package = input["package"] as? String {
            let trimmed = package.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if trimmed.contains(" ") || trimmed.contains("/") || trimmed.contains("..") {
                    return .failure("Invalid package name: must be a single dependency name without spaces, slashes, or '..'.")
                }
                args.append(trimmed)
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftPath)
        process.arguments = args
        process.currentDirectoryURL = context.workspaceRoot
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return .failure("Failed to start swift package update: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = stdout + "\n" + stderr
        let tail = String(combined.suffix(2000))
        let exitCode = process.terminationStatus
        if exitCode == 0 {
            return .success("swift package update succeeded (exit 0).\n\(tail)", data: ["exitCode": "\(exitCode)", "outputTail": tail])
        }
        return .failure("swift package update failed with exit code \(exitCode).\n\(tail)")
    }
}
