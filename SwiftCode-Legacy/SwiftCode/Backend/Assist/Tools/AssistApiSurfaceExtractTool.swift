import Foundation

public struct AssistApiSurfaceExtractTool: AssistTool {
    public let id = "api_surface_extract"
    public let name = "API Surface"
    public let description = "Extracts public/open declarations (func, class, struct, enum, protocol, actor, var, let, typealias, extension) from Swift files, grouped by file, with file:line locations and a total count."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Extracts the public/open API surface of Swift files.",
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
                "API Surface: no Swift files found.",
                data: ["scannedFiles": "0", "declarationCount": "0", "declarations": ""]
            )
        }

        guard let apiRegex = try? NSRegularExpression(pattern: "\\b(public|open)\\s+(?:\\w+\\s+)*?(func|class|struct|enum|protocol|actor|var|let|typealias|extension)\\b\\s*([A-Za-z_][A-Za-z0-9_]*)?", options: []) else {
            return .failure("API Surface: failed to build declaration pattern.")
        }

        var grouped: [String: [String]] = [:]
        var total = 0
        for url in files {
            guard let text = readFile(url) else { continue }
            let relative = relativePath(url, root: context.workspaceRoot)
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for match in apiRegex.matches(in: line, options: [], range: range) {
                    guard match.numberOfRanges >= 3,
                          let accessRange = Range(match.range(at: 1), in: line),
                          let kindRange = Range(match.range(at: 2), in: line) else { continue }
                    let access = String(line[accessRange])
                    let kind = String(line[kindRange])
                    var name = ""
                    if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound, let nameRange = Range(match.range(at: 3), in: line) {
                        name = String(line[nameRange])
                    }
                    let entry = name.isEmpty ? "\(relative):\(index + 1) \(access) \(kind)" : "\(relative):\(index + 1) \(access) \(kind) \(name)"
                    grouped[relative, default: []].append(entry)
                    total += 1
                    if total >= 1000 { break }
                }
                if total >= 1000 { break }
            }
            if total >= 1000 { break }
        }

        var output = "API Surface: scanned \(files.count) Swift file(s), found \(total) public/open declaration(s) across \(grouped.count) file(s).\n"
        if grouped.isEmpty {
            output += "No public/open declarations found."
        } else {
            for relative in grouped.keys.sorted() {
                output += "\n\(relative):\n"
                for entry in grouped[relative] ?? [] {
                    output += "  - \(entry)\n"
                }
            }
            if total >= 1000 {
                output += "\nListing capped at 1000 declarations."
            }
        }
        let flat = grouped.keys.sorted().flatMap { grouped[$0] ?? [] }.joined(separator: "\n")
        return .success(
            output,
            data: [
                "scannedFiles": "\(files.count)",
                "declarationCount": "\(total)",
                "declarations": flat
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
