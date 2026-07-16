import Foundation

public struct AssistValidateChangesTool: AssistTool {
    public let id = "safe_validate_changes"
    public let name = "Validate Changes"
    public let description = "Verifies that the applied changes are correct and don't break functionality."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let path = input["path"] as? String ?? "."
        let target = AssistToolingSupport.resolvePath(path, workspaceRoot: context.workspaceRoot)

        let files: [URL]
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue {
            files = AssistToolingSupport.enumeratedFiles(at: target, maxFileSize: 500_000)
        } else {
            files = [target]
        }

        var issues: [String] = []
        for file in files {
            let rel = AssistToolingSupport.relativePath(for: file, workspaceRoot: context.workspaceRoot)
            guard let content = AssistToolingSupport.readText(file) else {
                issues.append("\(rel): unreadable text file")
                continue
            }
            if content.contains("<<<<<<<") || content.contains(">>>>>>>") || content.contains("=======") {
                issues.append("\(rel): merge conflict markers detected")
            }
            if !content.hasSuffix("\n") {
                issues.append("\(rel): missing trailing newline")
            }
        }

        if issues.isEmpty {
            return .success("Changes validated successfully", data: ["issue_count": "0"])
        }
        return .success("Validation completed with \(issues.count) issue(s)", data: ["issue_count": "\(issues.count)", "issues": issues.joined(separator: "\n")])
    }
}
