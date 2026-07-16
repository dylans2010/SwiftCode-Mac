import Foundation

public struct AssistCodeSummaryTool: AssistTool {
    public let id = "code_summary"
    public let name = "Code Summary"
    public let description = "Provides a high-level summary of a file or directory."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        let targetURL = AssistToolingSupport.resolvePath(path, workspaceRoot: context.workspaceRoot)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            return .failure("Path does not exist: \(path)")
        }

        if isDirectory.boolValue {
            let files = AssistToolingSupport.enumeratedFiles(at: targetURL)
            let codeFiles = files.filter(AssistToolingSupport.isCodeFile)
            let summary = "Directory \(path): \(files.count) files, \(codeFiles.count) code files"
            return .success("Summary for \(path)", data: ["summary": summary])
        }

        guard let content = AssistToolingSupport.readText(targetURL) else {
            return .failure("File at \(path) is not readable as UTF-8 text")
        }

        let lines = content.components(separatedBy: CharacterSet.newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty }.count
        let commentLines = lines.filter { $0.trimmingCharacters(in: CharacterSet.whitespaces).hasPrefix("//") }.count
        let summary = "File \(path): \(lines.count) lines (\(nonEmpty) non-empty), \(commentLines) comment lines"
        return .success("Summary for \(path)", data: ["summary": summary])
    }
}
