import Foundation

public struct AssistTreeViewTool: AssistTool {
    public let id = "tree_view"
    public let name = "Tree View"
    public let description = "Generates a tree-like representation of the project structure."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Generates a tree-like representation of the project structure. Symlinks are listed as leaves, never followed (prevents symlink-cycle recursion). Output is capped; a truncation marker is appended when the cap is hit.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to render. Default: \".\" (workspace root)."),
                "maxDepth": JSONSchema(type: "integer", description: "Maximum tree depth. Clamped to 1...10. Default: 3.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        var maxDepth = 3
        if let raw = input["maxDepth"] {
            guard let parsed = Self.parseDepth(raw) else {
                return .failure("Invalid maxDepth: must be an integer >= 1 (got '\(raw)').", code: .invalidInput)
            }
            maxDepth = min(max(parsed, 1), 10)
        }
        let path = (input["path"] as? String) ?? "."
        let rootURL: URL
        do {
            rootURL = try context.fileSystem.resolve(path)
        } catch {
            return .failure("Failed to render tree at \(path): \(error.localizedDescription)", code: .notFound)
        }

        var visited = Set<String>()
        var entryCount = 0
        var truncated = false
        let tree = generateTree(at: rootURL, depth: 0, maxDepth: maxDepth, visited: &visited, entryCount: &entryCount, truncated: &truncated)
        let suffix = truncated ? "\n… [truncated at 2000 entries]" : ""
        return .success("Project Tree generated", data: [
            "tree": tree + suffix,
            "path": rootURL.path,
            "entries": "\(entryCount)",
            "truncated": truncated ? "true" : "false"
        ])
    }

    private func generateTree(at url: URL, depth: Int, maxDepth: Int, visited: inout Set<String>, entryCount: inout Int, truncated: inout Bool) -> String {
        if depth > maxDepth { return "" }
        if truncated { return "" }

        var result = ""
        let indent = String(repeating: "  ", count: depth)
        result += "\(indent)📂 \(url.lastPathComponent)\n"

        // Cycle guard: never descend into a canonical directory twice.
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath().path
        if visited.contains(canonical) {
            return result + "\(indent)  ↩︎ [already visited: \(url.lastPathComponent)]\n"
        }
        visited.insert(canonical)

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            for item in contents {
                if entryCount >= 2000 { truncated = true; break }
                entryCount += 1
                let isSymlink = (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
                if isSymlink {
                    result += "\(indent)  🔗 \(item.lastPathComponent)\n"
                } else if exists && isDir.boolValue {
                    result += generateTree(at: item, depth: depth + 1, maxDepth: maxDepth, visited: &visited, entryCount: &entryCount, truncated: &truncated)
                } else {
                    result += "\(indent)  📄 \(item.lastPathComponent)\n"
                }
            }
        } catch {
            result += "\(indent)  ⚠️ Error reading directory: \(error.localizedDescription)\n"
        }
        return result
    }

    private static func parseDepth(_ value: Any) -> Int? {
        if let i = value as? Int, i >= 1 { return i }
        if let d = value as? Double, d >= 1, d == d.rounded() { return Int(d) }
        if let s = value as? String, let i = Int(s.trimmingCharacters(in: .whitespaces)), i >= 1 { return i }
        return nil
    }
}
