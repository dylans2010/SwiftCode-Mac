import Foundation

public struct TreeViewTool {
    public static let identifier = "tree_view"

    public func run(directory: String, depth: Int = 2) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/tree"),
            arguments: ["-L", "\(depth)", directory]
        )
        if result.exitCode == 0 {
            return result.stdout
        } else {
             // Fallback if tree is not installed
             return try await manualTree(directory: directory, depth: depth)
        }
    }

    private func manualTree(directory: String, depth: Int, currentDepth: Int = 0) async throws -> String {
        if currentDepth > depth { return "" }
        let url = URL(fileURLWithPath: directory)
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        var output = ""
        for item in contents {
            let indent = String(repeating: "  ", count: currentDepth)
            output += "\(indent)\(item.lastPathComponent)\n"
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                output += try await manualTree(directory: item.path, depth: depth, currentDepth: currentDepth + 1)
            }
        }
        return output
    }
}
