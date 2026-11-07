import Foundation

public struct AssistProjectSchemeListTool: AssistTool {
    public let id = "project_scheme_list"
    public let name = "List Schemes"
    public let description = "Lists the Xcode schemes available for the user's project or workspace."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists the Xcode schemes available for the user's project or workspace.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        #if os(macOS)
        guard let project = locateProject(in: context.workspaceRoot) else {
            return .failure("No .xcodeproj or .xcworkspace found at the top level of the workspace.")
        }
        var args: [String] = project.isWorkspace
            ? ["-workspace", project.url.path]
            : ["-project", project.url.path]
        args += ["-list", "-json"]
        let result: (status: Int32, output: String)
        do {
            result = try runProcess(executable: "/usr/bin/xcodebuild", args: args, cwd: context.workspaceRoot.path)
        } catch {
            return .failure("Failed to run xcodebuild -list: \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            return .failure("xcodebuild -list failed: \(result.output)")
        }
        guard let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Failed to parse xcodebuild -list JSON output.")
        }
        var schemes: [String] = []
        if let projectDict = json["project"] as? [String: Any],
           let list = projectDict["schemes"] as? [String] {
            schemes += list
        }
        if let workspaceDict = json["workspace"] as? [String: Any],
           let list = workspaceDict["schemes"] as? [String] {
            schemes += list
        }
        let unique = Array(Set(schemes)).sorted()
        return .success(
            "Found \(unique.count) scheme(s): \(unique.joined(separator: ", "))",
            data: ["schemes": unique.joined(separator: ","), "count": "\(unique.count)", "project": project.url.lastPathComponent]
        )
        #else
        return .failure("Listing Xcode schemes requires macOS with xcodebuild.")
        #endif
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
        if let ws = workspaces.first {
            return LocatedBundle(url: ws, isWorkspace: true)
        }
        let projects = entries.filter { $0.pathExtension == "xcodeproj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let proj = projects.first {
            return LocatedBundle(url: proj, isWorkspace: false)
        }
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
