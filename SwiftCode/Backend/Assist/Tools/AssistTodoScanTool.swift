import Foundation

public struct AssistTodoScanTool: AssistTool {
    public let id = "todo_scan"
    public let name = "TODO Scan"
    public let description = "Scans Swift source files for TODO, FIXME, XXX, and HACK markers and returns a file:line:text list with counts per tag."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans Swift files for TODO/FIXME/XXX/HACK markers.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of a file or directory to scan. Defaults to the workspace root.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let root = resolvePath(input["path"] as? String, in: context) else {
            return .failure("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let files = enumerateSwiftFiles(at: root)
        if files.isEmpty {
            return .success(
                "TODO Scan: no Swift files found.",
                data: ["scannedFiles": "0", "totalMarkers": "0", "todo": "0", "fixme": "0", "xxx": "0", "hack": "0", "findings": ""]
            )
        }

        guard let tagRegex = try? NSRegularExpression(pattern: "\\b(TODO|FIXME|XXX|HACK)\\b[\\s:]*([^\\n]*)", options: []) else {
            return .failure("TODO Scan: failed to build marker pattern.")
        }

        var counts: [String: Int] = ["TODO": 0, "FIXME": 0, "XXX": 0, "HACK": 0]
        var findings: [String] = []
        for url in files {
            guard let text = readFile(url) else { continue }
            let relative = relativePath(url, root: context.workspaceRoot)
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for match in tagRegex.matches(in: line, options: [], range: range) {
                    guard match.numberOfRanges >= 3,
                          let tagRange = Range(match.range(at: 1), in: line),
                          let textRange = Range(match.range(at: 2), in: line) else { continue }
                    let tag = String(line[tagRange])
                    let markerText = String(line[textRange]).trimmingCharacters(in: .whitespaces)
                    counts[tag, default: 0] += 1
                    findings.append("\(relative):\(index + 1) \(tag): \(markerText)")
                    if findings.count >= 1000 { break }
                }
                if findings.count >= 1000 { break }
            }
            if findings.count >= 1000 { break }
        }

        let total = counts.values.reduce(0, +)
        var output = "TODO Scan: scanned \(files.count) Swift file(s), found \(total) marker(s) — TODO: \(counts["TODO"] ?? 0), FIXME: \(counts["FIXME"] ?? 0), XXX: \(counts["XXX"] ?? 0), HACK: \(counts["HACK"] ?? 0).\n"
        if findings.isEmpty {
            output += "No TODO/FIXME/XXX/HACK markers found."
        } else {
            output += findings.joined(separator: "\n")
            if total > findings.count {
                output += "\n… and \(total - findings.count) more marker(s) omitted (listing capped at 1000)."
            }
        }
        return .success(
            output,
            data: [
                "scannedFiles": "\(files.count)",
                "totalMarkers": "\(total)",
                "todo": "\(counts["TODO"] ?? 0)",
                "fixme": "\(counts["FIXME"] ?? 0)",
                "xxx": "\(counts["XXX"] ?? 0)",
                "hack": "\(counts["HACK"] ?? 0)",
                "findings": findings.joined(separator: "\n")
            ]
        )
    }

    private func resolvePath(_ raw: String?, in context: AssistContext) -> URL? {
        let workspace = context.workspaceRoot.standardized
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return workspace }
        if raw.contains("..") { return nil }
        let candidate: URL
        if raw.hasPrefix("/") {
            candidate = URL(fileURLWithPath: raw).standardized
        } else {
            candidate = workspace.appendingPathComponent(raw).standardized
        }
        if candidate == workspace || candidate.path.hasPrefix(workspace.path + "/") {
            return candidate
        }
        return nil
    }

    private func enumerateSwiftFiles(at root: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            if root.pathExtension.lowercased() == "swift" && fileSize(root) <= 300_000 {
                return [root]
            }
            return []
        }
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return results }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if name == ".git" || name == "DerivedData" || name == ".build" || name == "Pods" || name == "node_modules" {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension.lowercased() != "swift" { continue }
            if fileSize(url) > 300_000 { continue }
            results.append(url)
            if results.count >= 5000 { break }
        }
        return results.sorted { $0.path < $1.path }
    }

    private func fileSize(_ url: URL) -> Int {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
            return size
        }
        return 0
    }

    private func readFile(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardized.path
        let path = url.standardized.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}
