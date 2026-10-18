import Foundation

public struct AssistDeadCodeScanTool: AssistTool {
    public let id = "dead_code_scan"
    public let name = "Dead Code Scan"
    public let description = "Heuristic scan for Swift declarations that appear to have no references outside their own declaration line. Excludes public/open API, @main entry points, overrides, and well-known lifecycle names. Findings are heuristic leads, not proof of dead code."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans Swift files for declarations with no other whole-word references.",
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
                "Dead Code Scan: no Swift files found.",
                data: ["scannedFiles": "0", "declarationCount": "0", "candidateCount": "0", "candidates": ""]
            )
        }

        var entries: [(relative: String, lines: [String], text: String)] = []
        for url in files {
            guard let text = readFile(url) else { continue }
            entries.append((relative: relativePath(url, root: context.workspaceRoot), lines: text.components(separatedBy: "\n"), text: text))
        }

        // Whole-word occurrence counts across the entire scanned corpus.
        var wordCounts: [String: Int] = [:]
        let separators = CharacterSet.alphanumerics.inverted
        for entry in entries {
            for word in entry.text.components(separatedBy: separators) where !word.isEmpty {
                wordCounts[word, default: 0] += 1
            }
        }

        guard let declRegex = try? NSRegularExpression(pattern: "\\b(?:func|class|struct|enum|protocol|let|var|typealias|actor)\\s+([A-Za-z_][A-Za-z0-9_]*)", options: []) else {
            return .failure("Dead Code Scan: failed to build declaration pattern.")
        }
        guard let exclusionRegex = try? NSRegularExpression(pattern: "\\b(public|open|override)\\b|@main|@IBAction|@objc|PreviewProvider", options: []) else {
            return .failure("Dead Code Scan: failed to build exclusion pattern.")
        }
        let excludedNames: Set<String> = ["main", "App", "init", "deinit", "body", "preview"]

        var candidates: [(relative: String, line: Int, kind: String, name: String, count: Int)] = []
        var declarationCount = 0
        for entry in entries {
            for (index, line) in entry.lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for match in declRegex.matches(in: line, options: [], range: range) {
                    guard match.numberOfRanges >= 2, let nameRange = Range(match.range(at: 1), in: line) else { continue }
                    guard let fullRange = Range(match.range, in: line) else { continue }
                    let name = String(line[nameRange])
                    let kind = String(line[fullRange]).components(separatedBy: .whitespaces).first ?? "decl"
                    declarationCount += 1
                    if excludedNames.contains(name) { continue }
                    if exclusionRegex.firstMatch(in: line, options: [], range: range) != nil { continue }
                    let references = wordCounts[name] ?? 0
                    // The declaration line itself contributes one mention. A total
                    // of 1 means nothing else in the scanned corpus mentions it.
                    if references <= 1 {
                        candidates.append((relative: entry.relative, line: index + 1, kind: kind, name: name, count: references))
                    }
                }
            }
        }

        let capped = Array(candidates.prefix(200))
        var output = "Dead Code Scan (heuristic): scanned \(entries.count) Swift file(s), found \(declarationCount) declaration(s), \(candidates.count) candidate(s) with no other whole-word references.\n"
        output += "Names declared more than once (for example overloads) are not flagged, and references in strings or comments still count as mentions.\n"
        if capped.isEmpty {
            output += "No dead-code candidates found."
        } else {
            for candidate in capped {
                output += "- \(candidate.relative):\(candidate.line) \(candidate.kind) \(candidate.name) (corpus mentions: \(candidate.count))\n"
            }
            if candidates.count > capped.count {
                output += "… and \(candidates.count - capped.count) more candidate(s) omitted from this listing.\n"
            }
        }
        let candidateText = capped.map { "\($0.relative):\($0.line) \($0.kind) \($0.name)" }.joined(separator: "\n")
        return .success(
            output,
            data: [
                "scannedFiles": "\(entries.count)",
                "declarationCount": "\(declarationCount)",
                "candidateCount": "\(candidates.count)",
                "candidates": candidateText
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
