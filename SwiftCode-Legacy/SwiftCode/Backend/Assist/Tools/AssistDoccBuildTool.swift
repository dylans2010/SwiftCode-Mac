import Foundation

public struct AssistDoccBuildTool: AssistTool {
    public let id = "docc_build"
    public let name = "Build DocC Docs"
    public let description = "Builds DocC documentation with xcodebuild docbuild and verifies a .doccarchive was produced."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Builds DocC docs for a scheme. outputPath, when given, is the workspace-relative derived-data directory.",
            properties: [
                "scheme": JSONSchema(type: "string", description: "The scheme to document (required)."),
                "destination": JSONSchema(type: "string", description: "xcodebuild destination. Default is platform=macOS."),
                "outputPath": JSONSchema(type: "string", description: "Workspace-relative derived-data directory (optional). Default is .docc-derived.")
            ],
            required: ["scheme"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawScheme = input["scheme"] as? String, !rawScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: scheme")
        }
        let scheme = rawScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.contains("\n") && !scheme.contains("\r") else {
            return .failure("Invalid scheme: scheme must not contain newlines.")
        }
        let destination = (input["destination"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveDestination = (destination?.isEmpty == false) ? destination! : "platform=macOS"

        let derivedDataURL: URL
        if let rawOutput = input["outputPath"] as? String, !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolved = resolveInsideWorkspace(rawOutput, workspaceRoot: context.workspaceRoot) else {
                return .failure("Invalid outputPath: '\(rawOutput)' must be a workspace-relative path without '..' and must stay inside the workspace.")
            }
            derivedDataURL = resolved
        } else {
            derivedDataURL = context.workspaceRoot.appendingPathComponent(".docc-derived")
        }

        let xcodebuildPath = "/usr/bin/xcodebuild"
        guard FileManager.default.fileExists(atPath: xcodebuildPath) else {
            return .failure("xcodebuild not found at /usr/bin/xcodebuild. Install Xcode command line tools first.")
        }
        let arguments = [
            "docbuild",
            "-scheme", scheme,
            "-destination", effectiveDestination,
            "-derivedDataPath", derivedDataURL.path
        ]
        let (exitCode, _, stderr) = runProcess(
            executablePath: xcodebuildPath,
            arguments: arguments,
            workingDirectory: context.workspaceRoot
        )
        guard exitCode == 0 else {
            return .failure("xcodebuild docbuild failed (exit \(exitCode), scheme: \(scheme)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(2000))")
        }
        let archives = findDoccArchives(under: derivedDataURL)
        guard let archive = archives.sorted(by: { $0.path < $1.path }).first else {
            return .failure("xcodebuild docbuild succeeded but no .doccarchive was found under \(derivedDataURL.path).")
        }
        let relativeArchive = relativePath(for: archive, workspaceRoot: context.workspaceRoot)
        return .success("DocC build succeeded for scheme \(scheme). Archive: \(relativeArchive)", data: [
            "scheme": scheme,
            "destination": effectiveDestination,
            "archive_path": archive.path,
            "archive_relative": relativeArchive
        ])
    }

    private func findDoccArchives(under root: URL) -> [URL] {
        var found: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return found
        }
        for case let url as URL in enumerator {
            if url.pathExtension == "doccarchive" {
                found.append(url)
                enumerator.skipDescendants()
            }
        }
        return found
    }

    private func resolveInsideWorkspace(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(separator: "/").map(String.init)
        if components.contains("..") { return nil }
        if trimmed.hasPrefix("/") {
            guard trimmed == workspaceRoot.path || trimmed.hasPrefix(workspaceRoot.path + "/") else { return nil }
            return URL(fileURLWithPath: trimmed)
        }
        return workspaceRoot.appendingPathComponent(trimmed)
    }

    private func relativePath(for url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.path
        if url.path == root { return "." }
        if url.path.hasPrefix(root + "/") {
            return String(url.path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }

    private func runProcess(executablePath: String, arguments: [String], workingDirectory: URL?) -> (exitCode: Int32, stdout: String, stderr: String) {
        AssistToolingSupport.runProcess(executablePath: executablePath, arguments: arguments, workingDirectory: workingDirectory)
    }
}
