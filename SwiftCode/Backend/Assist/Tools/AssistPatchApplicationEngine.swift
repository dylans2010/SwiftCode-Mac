import Foundation

public struct AssistPatchApplicationEngine: AssistTool {
    public let id = "patch_application_engine"
    public let name = "Patch Application Engine"
    public let description = "Generates and applies line-level patches with integrity validation."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else { return .failure("Missing path") }
        guard let originalBlock = input["original"] as? String, let newBlock = input["updated"] as? String else {
            return .failure("Missing patch blocks: original/updated")
        }

        let content = try context.fileSystem.readFile(at: path)
        guard content.contains(originalBlock) else { return .failure("Patch integrity check failed: original block not found") }
        let patched = content.replacingOccurrences(of: originalBlock, with: newBlock)
        let diff = unifiedDiff(old: content, new: patched, file: path)
        try context.fileSystem.writeFile(at: path, content: patched)

        return .success("Patch applied to \(path)", data: ["diff": diff])
    }

    private func unifiedDiff(old: String, new: String, file: String) -> String {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)
        var lines = ["--- a/\(file)", "+++ b/\(file)"]
        let maxCount = max(oldLines.count, newLines.count)
        for i in 0..<maxCount {
            let oldLine = i < oldLines.count ? oldLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil
            if oldLine != newLine {
                if let oldLine { lines.append("-\(oldLine)") }
                if let newLine { lines.append("+\(newLine)") }
            }
        }
        return lines.joined(separator: "\n")
    }
}
