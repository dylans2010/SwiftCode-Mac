import Foundation

public struct AssistReadDirectoryTool: AssistTool {
    public let id = "dir_read"
    public let name = "Read Directory"
    public let description = "Lists the contents of a directory (native ls equivalent). Returns sorted entries with directory markers, entry count, and the resolved path. Non-recursive — use tree_view for a recursive listing."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists the contents of a directory. Returns sorted entries; directory entries are suffixed with '/'.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the directory to list. Use \".\" for the session working directory.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path", code: .missingArgument)
        }

        do {
            let contents = try context.fileSystem.listDirectory(at: path).sorted()
            let resolvedPath = (try? context.fileSystem.resolve(path).path) ?? path
            // Annotate directories with a trailing "/" so the model can tell
            // files from directories without a second tool call.
            var annotated: [String] = []
            for entry in contents {
                let child = path == "." || path.isEmpty ? entry : (path as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                let existsAsDir: Bool
                if let childURL = try? context.fileSystem.resolve(child) {
                    existsAsDir = FileManager.default.fileExists(atPath: childURL.path, isDirectory: &isDir) && isDir.boolValue
                } else {
                    existsAsDir = false
                }
                annotated.append(existsAsDir ? entry + "/" : entry)
            }
            return .success(
                "Successfully read directory: \(path) (\(contents.count) entries)",
                data: [
                    "contents": annotated.joined(separator: "\n"),
                    "count": "\(contents.count)",
                    "path": resolvedPath
                ]
            )
        } catch {
            return .failure("Failed to read directory at \(path): \(error.localizedDescription)", code: .executionFailed)
        }
    }
}
