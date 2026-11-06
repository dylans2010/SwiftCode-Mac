//
//  AssistRegexReplaceInFilesTool.swift
//  SwiftCode
//

import Foundation

public struct AssistRegexReplaceInFilesTool: AssistTool {
    public let id = "regex_replace_in_files"
    public let name = "Regex Replace in Files"
    public let description = "Performs regular expression search and replace across multiple workspace files with dry-run support."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Regex search and replace across workspace files matching file extension or directory scope.",
            properties: [
                "pattern": JSONSchema(type: "string", description: "Regular expression pattern to find."),
                "replacement": JSONSchema(type: "string", description: "Replacement string (supports $1, $2 capturing group templates)."),
                "fileExtension": JSONSchema(type: "string", description: "File extension filter (e.g. 'swift', 'json', 'md'). Defaults to 'swift'."),
                "dryRun": JSONSchema(type: "boolean", description: "If true, only reports changes without writing to disk. Defaults to false.")
            ],
            required: ["pattern", "replacement"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pattern = input["pattern"] as? String else {
            return .failure("Missing required parameter: pattern")
        }
        guard let replacement = input["replacement"] as? String else {
            return .failure("Missing required parameter: replacement")
        }
        let ext = (input["fileExtension"] as? String) ?? "swift"
        let dryRun = (input["dryRun"] as? Bool) ?? false

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return .failure("Invalid regular expression pattern: \(pattern)")
        }

        let root = context.workspaceRoot
        var modifiedFiles: [String] = []
        var totalReplacements = 0

        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == ext else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let nsString = content as NSString
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
            if !matches.isEmpty {
                let replaced = regex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: replacement)
                let rel = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                modifiedFiles.append("`\(rel)` (\(matches.count) matches)")
                totalReplacements += matches.count

                if !dryRun {
                    try? replaced.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }
        }

        if modifiedFiles.isEmpty {
            return .success("No matches found for pattern `\(pattern)` in *.\(ext) files.")
        }

        let prefix = dryRun ? "[DRY RUN] Would modify" : "Successfully modified"
        var report = "\(prefix) \(modifiedFiles.count) file(s) with \(totalReplacements) total replacements:\n\n"
        for f in modifiedFiles.prefix(30) {
            report += "- \(f)\n"
        }
        return .success(report)
    }
}
