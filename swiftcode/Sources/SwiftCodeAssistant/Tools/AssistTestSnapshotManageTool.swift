import Foundation

public struct AssistTestSnapshotManageTool: AssistTool {
    public let id = "test_snapshot_manage"
    public let name = "Manage Test Snapshots"
    public let description = "Lists snapshot test reference images under __Snapshots__ directories, or deletes unreferenced snapshot files when confirm is true."

    public init() {}

    public var capability: ToolCapability { .testing }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists snapshot references, or cleans unreferenced snapshot files with explicit confirmation.",
            properties: [
                "action": JSONSchema(type: "string", description: "list or clean. Default: list."),
                "confirm": JSONSchema(type: "string", description: "Must be 'true' for clean. Any other value refuses to delete.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let action = ((input["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "list"
        guard action == "list" || action == "clean" else {
            return .failure("action must be 'list' or 'clean'.")
        }
        let snapshotFiles = findSnapshotFiles(in: context.workspaceRoot)
        if action == "list" {
            if snapshotFiles.isEmpty {
                return .success("No snapshot files found under any __Snapshots__ directory in the workspace.", data: ["count": "0"])
            }
            var output = "Snapshot references: \(snapshotFiles.count) file(s) under __Snapshots__ directories."
            for file in snapshotFiles {
                output += "\n- \(relativePath(of: file, workspaceRoot: context.workspaceRoot))"
            }
            return .success(output, data: [
                "count": "\(snapshotFiles.count)",
                "files": snapshotFiles.map { relativePath(of: $0, workspaceRoot: context.workspaceRoot) }.joined(separator: ",")
            ])
        }

        let confirm = (input["confirm"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard confirm == "true" else {
            return .failure("clean requires confirm='true'. No files were deleted.")
        }
        if snapshotFiles.isEmpty {
            return .success("No snapshot files found. Nothing to clean.", data: ["deletedCount": "0"])
        }
        let sourceText = collectSwiftSourceText(in: context.workspaceRoot)
        var deleted: [String] = []
        var kept: [String] = []
        for file in snapshotFiles {
            if isReferenced(file, in: sourceText) {
                kept.append(relativePath(of: file, workspaceRoot: context.workspaceRoot))
            } else {
                do {
                    try FileManager.default.removeItem(at: file)
                    deleted.append(relativePath(of: file, workspaceRoot: context.workspaceRoot))
                } catch {
                    kept.append(relativePath(of: file, workspaceRoot: context.workspaceRoot) + " (delete failed: \(error.localizedDescription))")
                }
            }
        }
        var output = "Snapshot clean: deleted \(deleted.count) unreferenced file(s), kept \(kept.count)."
        if !deleted.isEmpty {
            output += "\nDeleted:\n" + deleted.map { "- \($0)" }.joined(separator: "\n")
        }
        if !kept.isEmpty {
            output += "\nKept:\n" + kept.map { "- \($0)" }.joined(separator: "\n")
        }
        return .success(output, data: [
            "deletedCount": "\(deleted.count)",
            "keptCount": "\(kept.count)",
            "deleted": deleted.joined(separator: ",")
        ])
    }

    private func findSnapshotFiles(in workspaceRoot: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: workspaceRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == "build" || name == "DerivedData" || name == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathComponents.contains("__Snapshots__") else { continue }
            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "gif", "txt", "json"].contains(ext) else { continue }
            results.append(url)
        }
        return results.sorted { $0.path < $1.path }
    }

    private func collectSwiftSourceText(in workspaceRoot: URL) -> String {
        var combined = ""
        guard let enumerator = FileManager.default.enumerator(at: workspaceRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return "" }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == "build" || name == "DerivedData" || name == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "swift" else { continue }
            if url.pathComponents.contains("__Snapshots__") { continue }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                combined += "\n" + text
            }
        }
        return combined
    }

    private func isReferenced(_ file: URL, in sourceText: String) -> Bool {
        let base = file.deletingPathExtension().lastPathComponent
        if base.isEmpty { return false }
        if sourceText.contains(base) { return true }
        let parts = base.components(separatedBy: ".").filter { !$0.isEmpty }
        for part in parts where part.count >= 3 {
            if sourceText.contains(part) { return true }
        }
        let stripped = base.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if stripped.count >= 3 && sourceText.contains(stripped) { return true }
        return false
    }

    private func relativePath(of url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        return url.lastPathComponent
    }
}
