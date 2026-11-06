import Foundation

public struct AssistProjectArchiveTool: AssistTool {
    public let id = "project_archive"
    public let name = "Archive Project"
    public let description = "Archives the user's Xcode project with xcodebuild archive and verifies the .xcarchive exists."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Archives the Xcode project with xcodebuild archive.",
            properties: [
                "scheme": JSONSchema(type: "string", description: "Scheme to archive. Required."),
                "configuration": JSONSchema(type: "string", description: "Build configuration, e.g. Release or Debug. Default: Release."),
                "archivePath": JSONSchema(type: "string", description: "Workspace-relative destination path for the .xcarchive. Required, must stay inside the workspace."),
                "exportOptionsPlist": JSONSchema(type: "string", description: "Optional workspace-relative path to an ExportOptions.plist (not used by archive; reserved for export steps).")
            ],
            required: ["scheme", "archivePath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        #if os(macOS)
        guard let scheme = (input["scheme"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !scheme.isEmpty else {
            return .failure("Missing required parameter: scheme")
        }
        guard let rawArchivePath = (input["archivePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawArchivePath.isEmpty else {
            return .failure("Missing required parameter: archivePath")
        }
        let configuration = (input["configuration"] as? String ?? "Release").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configuration.isEmpty else { return .failure("Missing required parameter: configuration") }
        if let exportPlist = (input["exportOptionsPlist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !exportPlist.isEmpty {
            guard let resolved = resolvedURL(for: exportPlist, workspaceRoot: context.workspaceRoot),
                  FileManager.default.fileExists(atPath: resolved.path) else {
                return .failure("exportOptionsPlist '\(exportPlist)' not found inside the workspace.")
            }
        }
        guard let archiveURL = resolvedURL(for: rawArchivePath, workspaceRoot: context.workspaceRoot) else {
            return .failure("archivePath '\(rawArchivePath)' is outside the workspace or contains '..'.")
        }
        guard archiveURL.pathExtension == "xcarchive" else {
            return .failure("archivePath must end in .xcarchive.")
        }
        guard let project = locateProject(in: context.workspaceRoot) else {
            return .failure("No .xcodeproj or .xcworkspace found at the top level of the workspace.")
        }
        let parentDir = archiveURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            return .failure("Failed to create archive parent directory: \(error.localizedDescription)")
        }
        var args: [String] = project.isWorkspace
            ? ["-workspace", project.url.path]
            : ["-project", project.url.path]
        args += ["-scheme", scheme, "-configuration", configuration, "-archivePath", archiveURL.path, "archive"]
        let result: (status: Int32, output: String)
        do {
            result = try runProcess(executable: "/usr/bin/xcodebuild", args: args, cwd: context.workspaceRoot.path)
        } catch {
            return .failure("Failed to run xcodebuild archive: \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            return .failure("xcodebuild archive failed (exit \(result.status)): \(result.output)")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: archiveURL.path, isDirectory: &isDir), isDir.boolValue else {
            return .failure("Verification failed: .xcarchive not found at '\(rawArchivePath)' after a successful xcodebuild run.")
        }
        return .success(
            "Archived scheme '\(scheme)' to '\(rawArchivePath)' (exit 0).",
            data: ["archivePath": rawArchivePath, "scheme": scheme, "configuration": configuration, "exitCode": "\(result.status)"]
        )
        #else
        return .failure("Archiving requires macOS with xcodebuild.")
        #endif
    }

    private func resolvedURL(for path: String, workspaceRoot: URL) -> URL? {
        if path.contains("..") { return nil }
        if path.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: path).standardized
            guard candidate.path == workspaceRoot.standardized.path || candidate.path.hasPrefix(workspaceRoot.standardized.path + "/") else { return nil }
            return candidate
        }
        let candidate = workspaceRoot.appendingPathComponent(path).standardized
        guard candidate.path == workspaceRoot.standardized.path || candidate.path.hasPrefix(workspaceRoot.standardized.path + "/") else { return nil }
        return candidate
    }

    private struct LocatedBundle {
        let url: URL
        let isWorkspace: Bool
    }

    private func locateProject(in workspaceRoot: URL) -> LocatedBundle? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let workspaces = entries.filter { $0.pathExtension == "xcworkspace" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let ws = workspaces.first { return LocatedBundle(url: ws, isWorkspace: true) }
        let projects = entries.filter { $0.pathExtension == "xcodeproj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let proj = projects.first { return LocatedBundle(url: proj, isWorkspace: false) }
        return nil
    }

    #if os(macOS)
    private func runProcess(executable: String, args: [String], cwd: String) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
    #endif
}
