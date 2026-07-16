import Foundation

public struct AssistFormatCodeTool: AssistTool {
    public let id = "code_format"
    public let name = "Format Code"
    public let description = "Formats the code according to project style guidelines."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let path = input["path"] as? String ?? "."
        let targetURL = AssistToolingSupport.resolvePath(path, workspaceRoot: context.workspaceRoot)
        var isDir: ObjCBool = false

        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            return .failure("Path does not exist: \(path)")
        }

        let files: [URL]
        if isDir.boolValue {
            files = AssistToolingSupport.enumeratedFiles(at: targetURL, allowedExtensions: ["swift", "m", "h", "c", "cpp", "js", "ts", "py"])
        } else {
            files = [targetURL]
        }

        var formattedCount = 0
        for file in files {
            guard let content = AssistToolingSupport.readText(file) else { continue }
            let formatted = simpleFormat(content)
            if formatted != content {
                let relative = AssistToolingSupport.relativePath(for: file, workspaceRoot: context.workspaceRoot)
                try context.fileSystem.writeFile(at: relative, content: formatted)
                formattedCount += 1
            }
        }

        return .success("Code formatting completed at \(path)", data: ["formatted_files": "\(formattedCount)"])
    }

    private func simpleFormat(_ content: String) -> String {
        var result: [String] = []
        var previousBlank = false
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ").trimmingCharacters(in: .whitespaces)
            let isBlank = line.isEmpty
            if isBlank {
                if !previousBlank { result.append("") }
            } else {
                result.append(line)
            }
            previousBlank = isBlank
        }
        return result.joined(separator: "\n") + "\n"
    }
}
