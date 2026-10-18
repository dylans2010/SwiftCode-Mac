//
//  AssistTodoFixmeScannerTool.swift
//  SwiftCode
//

import Foundation

public struct AssistTodoFixmeScannerTool: AssistTool {
    public let id = "todo_fixme_scanner"
    public let name = "TODO & FIXME Scanner"
    public let description = "Scans workspace files to index all TODO, FIXME, MARK, HACK, and BUG annotations."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Finds action items (TODO, FIXME, BUG, HACK, MARK) across workspace source files.",
            properties: [
                "tag": JSONSchema(type: "string", description: "Optional specific tag filter: 'TODO', 'FIXME', 'BUG', 'HACK', or 'MARK'."),
                "maxResults": JSONSchema(type: "integer", description: "Maximum number of results to return (default: 50).")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let tagFilter = input["tag"] as? String
        let maxResults = (input["maxResults"] as? Int) ?? 50

        let root = context.workspaceRoot
        var results: [(tag: String, file: String, line: Int, text: String)] = []

        let targets = ["TODO:", "FIXME:", "BUG:", "HACK:", "MARK:"]
        let activeTags = tagFilter != nil ? ["\(tagFilter!.uppercased()):"] : targets

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" || fileURL.pathExtension == "m" || fileURL.pathExtension == "h" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let relPath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            let lines = text.components(separatedBy: .newlines)

            for (idx, line) in lines.enumerated() {
                for t in activeTags {
                    if let range = line.range(of: t) {
                        let snippet = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                        results.append((tag: t.replacingOccurrences(of: ":", with: ""), file: relPath, line: idx + 1, text: snippet))
                        if results.count >= maxResults { break }
                    }
                }
                if results.count >= maxResults { break }
            }
            if results.count >= maxResults { break }
        }

        if results.isEmpty {
            return .success("No TODO/FIXME/BUG annotations found in workspace.")
        }

        var report = "### Workspace Action Items (\(results.count) found):\n\n"
        let grouped = Dictionary(grouping: results, by: { $0.tag })
        for tag in grouped.keys.sorted() {
            report += "#### \(tag) (\(grouped[tag]!.count)):\n"
            for item in grouped[tag]! {
                report += "- `\(item.file):\(item.line)` → \(item.text)\n"
            }
            report += "\n"
        }

        return .success(report)
    }
}
