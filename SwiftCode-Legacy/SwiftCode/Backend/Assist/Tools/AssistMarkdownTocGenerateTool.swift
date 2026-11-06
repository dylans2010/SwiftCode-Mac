import Foundation

public struct AssistMarkdownTocGenerateTool: AssistTool {
    public let id = "markdown_toc_generate"
    public let name = "Markdown TOC Generate"
    public let description = "Generates a table of contents from a Markdown file's headings and inserts or updates it between TOC markers."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Generates a table of contents.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative Markdown file."),
                "maxDepth": JSONSchema(type: "integer", description: "Heading depth to include. Default 3, max 6.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        let maxDepth = max(1, min(6, (input["maxDepth"] as? Int) ?? 3))
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot),
              var text = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure("Cannot read Markdown file at: \(raw)")
        }
        var entries: [(Int, String)] = []
        for line in text.components(separatedBy: .newlines) {
            guard line.hasPrefix("#") else { continue }
            let level = line.prefix(while: { $0 == "#" }).count
            guard level >= 1 && level <= maxDepth else { continue }
            let title = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            entries.append((level, title))
        }
        if entries.isEmpty {
            return .failure("No headings found in \(raw).")
        }
        func anchor(_ title: String) -> String {
            let lower = title.lowercased()
            let allowed = lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" }
            return String(String.UnicodeScalarView(allowed)).replacingOccurrences(of: " ", with: "-")
        }
        let tocLines = entries.map { (level, title) in
            String(repeating: "  ", count: level - 1) + "- [\(title)](#\(anchor(title)))"
        }
        let toc = "<!-- TOC -->\n" + tocLines.joined(separator: "\n") + "\n<!-- /TOC -->"
        if text.contains("<!-- TOC -->"), text.contains("<!-- /TOC -->"),
           let start = text.range(of: "<!-- TOC -->"), let end = text.range(of: "<!-- /TOC -->"), start.lowerBound < end.upperBound {
            text.replaceSubrange(start.lowerBound..<end.upperBound, with: toc)
        } else {
            // Insert after the first heading block.
            let lines = text.components(separatedBy: .newlines)
            if let firstHeading = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
                var mutable = lines
                mutable.insert("", at: firstHeading + 1)
                mutable.insert(toc, at: firstHeading + 2)
                text = mutable.joined(separator: "\n")
            } else {
                text = toc + "\n\n" + text
            }
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to write TOC to \(raw): \(error.localizedDescription)")
        }
        return .success("Table of contents (\(entries.count) entries) written to \(raw).", data: [
            "path": raw, "entryCount": "\(entries.count)"
        ], filesChanged: [raw])
    }
}
