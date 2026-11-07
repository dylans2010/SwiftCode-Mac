import Foundation

public struct AssistProjectCleanTool: AssistTool {
    public let id = "project_clean"
    public let name = "Clean Project"
    public let description = "Cleans the project: removes the workspace build directory and/or runs xcodebuild clean. Requires explicit confirmation."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .potentiallyDestructive }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Cleans the project build directory and/or runs xcodebuild clean.",
            properties: [
                "scope": JSONSchema(type: "string", description: "build, derivedData, or both. Default: build. build removes workspaceRoot/build only; derivedData runs xcodebuild clean."),
                "confirm": JSONSchema(type: "string", description: "Must be \"true\" to proceed. Any other value fails without doing anything.")
            ],
            required: ["confirm"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let confirmed: Bool
        if let boolValue = input["confirm"] as? Bool {
            confirmed = boolValue
        } else if let stringValue = input["confirm"] as? String {
            confirmed = stringValue.lowercased() == "true"
        } else {
            confirmed = false
        }
        guard confirmed else {
            return .failure("Clean requires confirm=\"true\". No changes were made.")
        }
        let scope = (input["scope"] as? String ?? "build").lowercased()
        guard scope == "build" || scope == "derivedData" || scope == "both" else {
            return .failure("Invalid scope '\(scope)'. Expected build, derivedData, or both.")
        }

        var removed: [String] = []
        var notes: [String] = []

        if scope == "build" || scope == "both" {
            let buildDir = context.workspaceRoot.appendingPathComponent("build").standardized
            let root = context.workspaceRoot.standardized
            guard buildDir.path == root.path + "/build" else {
                return .failure("Refusing to remove path outside the workspace.")
            }
            if FileManager.default.fileExists(atPath: buildDir.path) {
                do {
                    try FileManager.default.removeItem(at: buildDir)
                    removed.append("build/")
                } catch {
                    return .failure("Failed to remove build directory: \(error.localizedDescription)")
                }
            } else {
                notes.append("build/ did not exist.")
            }
        }

        if scope == "derivedData" || scope == "both" {
            #if os(macOS)
            guard let project = locateProject(in: context.workspaceRoot) else {
                return .failure("No .xcodeproj or .xcworkspace found at the top level of the workspace. Build directory removal (if requested) already completed.")
            }
            let args: [String] = project.isWorkspace
                ? ["-workspace", project.url.path, "clean"]
                : ["-project", project.url.path, "clean"]
            let result: (status: Int32, output: String)
            do {
                result = try runProcess(executable: "/usr/bin/xcodebuild", args: args, cwd: context.workspaceRoot.path)
            } catch {
                return .failure("Failed to run xcodebuild clean: \(error.localizedDescription)")
            }
            guard result.status == 0 else {
                return .failure("xcodebuild clean failed: \(result.output)")
            }
            removed.append("xcodebuild clean")
            #else
            return .failure("xcodebuild clean requires macOS.")
            #endif
        }

        let summary = removed.isEmpty
            ? "Nothing to clean. \(notes.joined(separator: " "))"
            : "Cleaned: \(removed.joined(separator: ", ")). \(notes.joined(separator: " "))"
        return .success(
            summary.trimmingCharacters(in: .whitespacesAndNewlines),
            data: ["removed": removed.joined(separator: ","), "scope": scope]
        )
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
