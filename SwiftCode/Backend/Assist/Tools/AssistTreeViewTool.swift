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
            description: "Generates a tree-like representation of the project structure.",
            properties: [
                "maxDepth": JSONSchema(type: "string", description: "Maximum tree depth as a decimal string. Unparseable values fall back to 3. Default: \"3\".")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let maxDepthStr = input["maxDepth"] as? String ?? "3"
        let maxDepth = Int(maxDepthStr) ?? 3

        let tree = generateTree(at: context.workspaceRoot, depth: 0, maxDepth: maxDepth)
        return .success("Project Tree generated", data: ["tree": tree])
    }

    private func generateTree(at url: URL, depth: Int, maxDepth: Int) -> String {
        if depth > maxDepth { return "" }

        var result = ""
        let indent = String(repeating: "  ", count: depth)
        result += "\(indent)📂 \(url.lastPathComponent)\n"

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    result += generateTree(at: item, depth: depth + 1, maxDepth: maxDepth)
                } else {
                    result += "\(indent)  📄 \(item.lastPathComponent)\n"
                }
            }
        } catch {
            result += "\(indent)  ⚠️ Error reading directory: \(error.localizedDescription)\n"
        }
        return result
    }
}
