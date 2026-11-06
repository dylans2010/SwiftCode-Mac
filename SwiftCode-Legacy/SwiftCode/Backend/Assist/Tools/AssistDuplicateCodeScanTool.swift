import Foundation

public struct AssistDuplicateCodeScanTool: AssistTool {
    public let id = "duplicate_code_scan"
    public let name = "Duplicate Code Scan"
    public let description = "Heuristic scan for duplicated blocks of Swift code. Lines are normalized (trimmed, blank lines and full-line comments and brace-only lines skipped) and compared with a sliding window. Findings are heuristic leads — duplicated blocks may be intentional."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Finds duplicated normalized code blocks of at least minLines lines.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of a file or directory to scan. Defaults to the workspace root."),
                "minLines": JSONSchema(type: "string", description: "Minimum normalized lines per block, as a decimal string. Clamped to at least 3. Default: \"6\".")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let root = resolvePath(input["path"] as? String, in: context) else {
            return .failure("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        var minLines = 6
        let rawMin = input["minLines"] ?? input["min_lines"]
        if let value = rawMin as? Int {
            minLines = value
        } else if let value = rawMin as? Double {
            minLines = Int(value)
        } else if let text = rawMin as? String, let value = Int(text.trimmingCharacters(in: .whitespaces)) {
            minLines = value
        }
        if minLines < 3 { minLines = 3 }

        let files = enumerateSwiftFiles(at: root)
        if files.isEmpty {
            return .success(
                "Duplicate Code Scan: no Swift files found.",
                data: ["scannedFiles": "0", "duplicateGroups": "0", "groups": ""]
            )
        }

        // Map normalized block key -> locations (file, start line).
        var windows: [String: [(file: String, line: Int)]] = [:]
        for url in files {
            guard let text = readFile(url) else { continue }
            let relative = relativePath(url, root: context.workspaceRoot)
            let normalized = normalizedLines(text)
            guard normalized.count >= minLines else { continue }
            for start in 0...(normalized.count - minLines) {
                let key = normalized[start..<(start + minLines)].map { $0.text }.joined(separator: "\n")
                windows[key, default: []].append((file: relative, line: normalized[start].line))
            }
        }

        // Keep groups seen in at least two locations, sorted earliest-first so
        // the deduplication below keeps the first window of each duplicated block.
        var groups: [(key: String, locations: [(file: String, line: Int)])] = []
        for (key, locations) in windows where locations.count >= 2 {
            groups.append((key: key, locations: locations))
        }
        groups.sort {
            let aMin = $0.locations.map { $0.line }.min() ?? 0
            let bMin = $1.locations.map { $0.line }.min() ?? 0
            if aMin != bMin { return aMin < bMin }
            return $0.locations.count > $1.locations.count
        }

        // Drop windows that are a shifted continuation of an already-kept group:
        // every location shifted by the same positive offset.
        var kept: [(key: String, locations: [(file: String, line: Int)])] = []
        for group in groups {
            var isContinuation = false
            for existing in kept where existing.locations.count == group.locations.count {
                var shift: Int? = nil
                var matches = true
                for (index, location) in group.locations.enumerated() {
                    let other = existing.locations[index]
                    if other.file != location.file { matches = false; break }
                    let delta = location.line - other.line
                    if delta <= 0 { matches = false; break }
                    if let current = shift, current != delta { matches = false; break }
                    shift = delta
                }
                if matches { isContinuation = true; break }
            }
            if !isContinuation {
                kept.append(group)
            }
            if kept.count >= 100 { break }
        }

        var output = "Duplicate Code Scan (heuristic): scanned \(files.count) Swift file(s) with window size \(minLines) normalized line(s), found \(kept.count) duplicated block group(s).\n"
        var groupText = ""
        if kept.isEmpty {
            output += "No duplicated blocks found."
        } else {
            for group in kept {
                let header = "Duplicate block ×\(group.locations.count):"
                output += "\(header)\n"
                groupText += "\(header)\n"
                for location in group.locations {
                    output += "  - \(location.file):\(location.line)\n"
                    groupText += "  - \(location.file):\(location.line)\n"
                }
                let snippet = group.key.components(separatedBy: "\n").prefix(3).map { "    \($0)" }.joined(separator: "\n")
                output += "\(snippet)\n"
                groupText += "\(snippet)\n"
            }
        }
        return .success(
            output,
            data: [
                "scannedFiles": "\(files.count)",
                "duplicateGroups": "\(kept.count)",
                "groups": groupText
            ]
        )
    }

    private func normalizedLines(_ text: String) -> [(line: Int, text: String)] {
        let punctuation = Set<Character>(["{", "}", "(", ")", "[", "]", ",", ";", ":", "."])
        var result: [(line: Int, text: String)] = []
        for (index, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("//") { continue }
            if trimmed.allSatisfy({ punctuation.contains($0) }) { continue }
            result.append((line: index + 1, text: trimmed))
        }
        return result
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
