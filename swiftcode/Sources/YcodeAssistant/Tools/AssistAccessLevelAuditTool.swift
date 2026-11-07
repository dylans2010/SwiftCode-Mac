import Foundation

public struct AssistAccessLevelAuditTool: AssistTool {
    public let id = "access_level_audit"
    public let name = "Access Level Audit"
    public let description = "Counts Swift declarations by access level (public, open, internal, private, fileprivate; default internal when unspecified) and lists the files with the most public API. Heuristic: access is inferred from keywords on the declaration line, with public/open taking precedence over private(set)."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits declaration access levels across Swift files.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of a file or directory to audit. Defaults to the workspace root.")
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
                "Access Level Audit: no Swift files found.",
                data: ["scannedFiles": "0", "public": "0", "open": "0", "internal": "0", "private": "0", "fileprivate": "0", "total": "0"]
            )
        }

        guard let declRegex = try? NSRegularExpression(pattern: "\\b(func|class|struct|enum|protocol|actor|var|let|typealias|extension)\\b", options: []) else {
            return .failure("Access Level Audit: failed to build declaration pattern.")
        }

        var counts: [String: Int] = ["public": 0, "open": 0, "internal": 0, "private": 0, "fileprivate": 0]
        var publicPerFile: [String: Int] = [:]
        var total = 0
        for url in files {
            guard let text = readFile(url) else { continue }
            let relative = relativePath(url, root: context.workspaceRoot)
            for line in text.components(separatedBy: "\n") {
                let range = NSRange(line.startIndex..., in: line)
                guard declRegex.firstMatch(in: line, options: [], range: range) != nil else { continue }
                let level = accessLevel(of: line)
                counts[level, default: 0] += 1
                total += 1
                if level == "public" || level == "open" {
                    publicPerFile[relative, default: 0] += 1
                }
            }
        }

        let topPublic = publicPerFile.sorted { $0.value > $1.value }.prefix(10)
        var output = "Access Level Audit: scanned \(files.count) Swift file(s), \(total) declaration(s) — public: \(counts["public"] ?? 0), open: \(counts["open"] ?? 0), internal: \(counts["internal"] ?? 0), private: \(counts["private"] ?? 0), fileprivate: \(counts["fileprivate"] ?? 0).\n"
        if topPublic.isEmpty {
            output += "No public/open declarations found."
        } else {
            output += "Files with the most public/open API:\n"
            for entry in topPublic {
                output += "- \(entry.key): \(entry.value) public/open declaration(s)\n"
            }
        }
        let topText = topPublic.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return .success(
            output,
            data: [
                "scannedFiles": "\(files.count)",
                "public": "\(counts["public"] ?? 0)",
                "open": "\(counts["open"] ?? 0)",
                "internal": "\(counts["internal"] ?? 0)",
                "private": "\(counts["private"] ?? 0)",
                "fileprivate": "\(counts["fileprivate"] ?? 0)",
                "total": "\(total)",
                "topPublicFiles": topText
            ]
        )
    }

    private func accessLevel(of line: String) -> String {
        if containsWord(line, "public") { return "public" }
        if containsWord(line, "open") { return "open" }
        if containsWord(line, "fileprivate") { return "fileprivate" }
        if containsWord(line, "private") { return "private" }
        return "internal"
    }

    private func containsWord(_ line: String, _ word: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b", options: []) else { return false }
        let range = NSRange(line.startIndex..., in: line)
        return regex.firstMatch(in: line, options: [], range: range) != nil
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
