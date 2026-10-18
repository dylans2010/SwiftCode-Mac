import Foundation

public struct AssistSymbolRenameProjectTool: AssistTool {
    public let id = "symbol_rename_project"
    public let name = "Rename Symbol Project-Wide"
    public let description = "Renames a symbol across Swift files by replacing whole-word occurrences of oldName with newName. Only files that actually change are rewritten. Refuses when oldName equals newName or either name is not a valid Swift identifier."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Renames a symbol project-wide with whole-word replacement.",
            properties: [
                "oldName": JSONSchema(type: "string", description: "Existing symbol name to replace."),
                "newName": JSONSchema(type: "string", description: "New symbol name. Letters, digits, and underscores only; must not start with a digit."),
                "path": JSONSchema(type: "string", description: "Workspace-relative path of a file or directory to search. Defaults to the workspace root.")
            ],
            required: ["oldName", "newName"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let oldName = (input["oldName"] ?? input["old_name"]) as? String, !oldName.isEmpty else {
            return .failure("Missing required parameter: oldName")
        }
        guard let newName = (input["newName"] ?? input["new_name"]) as? String, !newName.isEmpty else {
            return .failure("Missing required parameter: newName")
        }
        guard isValidIdentifier(oldName) else {
            return .failure("Invalid oldName '\(oldName)': identifiers may contain only letters, digits, and underscores, and must not start with a digit.")
        }
        guard isValidIdentifier(newName) else {
            return .failure("Invalid newName '\(newName)': identifiers may contain only letters, digits, and underscores, and must not start with a digit.")
        }
        guard oldName != newName else {
            return .failure("Refusing rename: oldName and newName are identical ('\(oldName)').")
        }
        guard let root = resolvePath(input["path"] as? String, in: context) else {
            return .failure("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }

        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: oldName) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return .failure("Rename failed: could not build a whole-word pattern for '\(oldName)'.")
        }

        let files = enumerateSwiftFiles(at: root)
        if files.isEmpty {
            return .success(
                "Rename Symbol: no Swift files found.",
                data: ["filesChanged": "", "replacementCount": "0", "changedFileCount": "0"]
            )
        }

        var changed: [String] = []
        var totalReplacements = 0
        for url in files {
            guard let content = readFile(url) else { continue }
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.numberOfMatches(in: content, options: [], range: range)
            guard matches > 0 else { continue }
            let updated = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: newName)
            do {
                try updated.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return .failure("Rename failed while writing \(relativePath(url, root: context.workspaceRoot)): \(error.localizedDescription)")
            }
            changed.append(relativePath(url, root: context.workspaceRoot))
            totalReplacements += matches
        }

        if changed.isEmpty {
            return .success(
                "Rename Symbol: no whole-word occurrences of '\(oldName)' found in \(files.count) Swift file(s). Nothing changed.",
                data: ["filesChanged": "", "replacementCount": "0", "changedFileCount": "0"]
            )
        }
        return .success(
            "Rename Symbol: replaced \(totalReplacements) whole-word occurrence(s) of '\(oldName)' with '\(newName)' across \(changed.count) file(s):\n" + changed.map { "- \($0)" }.joined(separator: "\n"),
            data: [
                "filesChanged": changed.joined(separator: "\n"),
                "replacementCount": "\(totalReplacements)",
                "changedFileCount": "\(changed.count)"
            ],
            filesChanged: changed
        )
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "_"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard let first = value.unicodeScalars.first, !CharacterSet.decimalDigits.contains(first) else { return false }
        return true
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
