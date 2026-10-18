import Foundation

public struct AssistBinarySizeReportTool: AssistTool {
    public let id = "binary_size_report"
    public let name = "Binary Size Report"
    public let description = "Reports total size and the 10 largest files for each .app bundle under the workspace build directory or an explicit in-workspace path. DerivedData is never scanned."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Finds .app bundles under workspace build output or an explicit in-workspace path and sizes them.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional workspace-relative path to a .app bundle or a directory to search for .app bundles. Default: build/.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let pathRaw = ((input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "build/"
        guard let searchRoot = resolveInsideWorkspace(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("path must be inside the workspace and must not contain '..'.")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: searchRoot.path, isDirectory: &isDir) else {
            return .failure("Path not found at '\(pathRaw)'. Build the project first or pass a path to an existing .app bundle.")
        }
        var appBundles: [URL] = []
        if searchRoot.pathExtension == "app" {
            appBundles = [searchRoot]
        } else if isDir.boolValue {
            appBundles = findAppBundles(under: searchRoot)
        } else {
            return .failure("path '\(pathRaw)' is neither a .app bundle nor a directory.")
        }
        if appBundles.isEmpty {
            return .success("No .app bundles found under '\(pathRaw)'. DerivedData is intentionally never scanned.", data: ["appCount": "0", "totalBytes": "0"])
        }
        var output = "Binary size report: \(appBundles.count) .app bundle(s)."
        var grandTotal: Int64 = 0
        var summaryParts: [String] = []
        for app in appBundles.sorted(by: { $0.path < $1.path }) {
            let files = sizedFiles(in: app)
            let total = files.reduce(0) { $0 + $1.size }
            grandTotal += total
            let largest = files.sorted { $0.size > $1.size }.prefix(10)
            output += "\n\n\(relativePath(of: app, workspaceRoot: context.workspaceRoot)) — total \(formatBytes(total)) (\(total) bytes), \(files.count) file(s)"
            for entry in largest {
                output += "\n  - \(relativePath(of: entry.url, workspaceRoot: context.workspaceRoot)): \(formatBytes(entry.size)) (\(entry.size) bytes)"
            }
            summaryParts.append("\(app.lastPathComponent)=\(total)")
        }
        output += "\n\nGrand total: \(formatBytes(grandTotal)) (\(grandTotal) bytes)"
        return .success(output, data: [
            "appCount": "\(appBundles.count)",
            "totalBytes": "\(grandTotal)",
            "apps": summaryParts.joined(separator: ",")
        ])
    }

    private func findAppBundles(under root: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == "DerivedData" {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "app" {
                results.append(url)
                enumerator.skipDescendants()
            }
        }
        return results
    }

    private func sizedFiles(in app: URL) -> [(url: URL, size: Int64)] {
        var results: [(url: URL, size: Int64)] = []
        guard let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            if let size = values.fileSize {
                results.append((url: url, size: Int64(size)))
            }
        }
        return results
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1_048_576 {
            return String(format: "%.2f MB", value / 1_048_576)
        }
        if value >= 1_024 {
            return String(format: "%.1f KB", value / 1_024)
        }
        return "\(bytes) bytes"
    }

    private func resolveInsideWorkspace(_ rawPath: String, workspaceRoot: URL) -> URL? {
        if rawPath.isEmpty { return nil }
        if rawPath.components(separatedBy: "/").contains("..") { return nil }
        let root = workspaceRoot.standardized
        let candidate: URL
        if rawPath.hasPrefix("/") {
            candidate = URL(fileURLWithPath: rawPath).standardized
        } else {
            candidate = root.appendingPathComponent(rawPath).standardized
        }
        let rootPath = root.path
        if candidate.path == rootPath { return candidate }
        if candidate.path.hasPrefix(rootPath + "/") { return candidate }
        return nil
    }

    private func relativePath(of url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        return url.lastPathComponent
    }
}
