import Foundation

public struct AssistPackageManifestValidateTool: AssistTool {
    public let id = "package_manifest_validate"
    public let name = "Validate Package Manifest"
    public let description = "Validates Package.swift by running swift package dump-package and reporting the package name and target count."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Validates a Swift package manifest.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to Package.swift. Default: \"Package.swift\".")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let swiftPath = "/usr/bin/swift"
        guard FileManager.default.fileExists(atPath: swiftPath) else {
            return .failure("Swift not found at /usr/bin/swift.")
        }
        let rawPath = (input["path"] as? String) ?? "Package.swift"
        guard let manifestURL = resolvePath(rawPath, workspaceRoot: context.workspaceRoot) else {
            return .failure("Invalid path '\(rawPath)': must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .failure("Package manifest not found at '\(rawPath)'.")
        }
        let workingDir = manifestURL.deletingLastPathComponent()
        let root = context.workspaceRoot.standardizedFileURL
        guard workingDir.standardizedFileURL.path == root.path || workingDir.standardizedFileURL.path.hasPrefix(root.path + "/") else {
            return .failure("Manifest directory is outside the workspace.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftPath)
        process.arguments = ["package", "dump-package"]
        process.currentDirectoryURL = workingDir
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return .failure("Failed to start swift package dump-package: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let stdoutData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus
        if exitCode != 0 {
            let tail = String(stderr.suffix(2000))
            return .failure("Package manifest is invalid: swift package dump-package exited with code \(exitCode).\n\(tail)")
        }
        var packageName = "unknown"
        var targetCount = 0
        if let json = try? JSONSerialization.jsonObject(with: stdoutData) as? [String: Any] {
            if let name = json["name"] as? String {
                packageName = name
            }
            if let targets = json["targets"] as? [[String: Any]] {
                targetCount = targets.count
            }
        }
        return .success("Package manifest is valid: \(packageName) with \(targetCount) target(s).", data: ["packageName": packageName, "targetCount": "\(targetCount)", "exitCode": "\(exitCode)"])
    }

    private func resolvePath(_ rawPath: String, workspaceRoot: URL) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("..") { return nil }
        let root = workspaceRoot.standardizedFileURL
        if trimmed.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
            return candidate
        }
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }
}
