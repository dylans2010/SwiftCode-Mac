//
//  AssistSymbolReferenceGraphTool.swift
//  SwiftCode
//

import Foundation

public struct AssistSymbolReferenceGraphTool: AssistTool {
    public let id = "symbol_reference_graph"
    public let name = "Symbol Reference Graph"
    public let description = "Traverses workspace files to identify declarations, references, and call sites for a given Swift symbol."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Finds all occurrences, definitions, and references for a symbol across workspace source files.",
            properties: [
                "symbol": JSONSchema(type: "string", description: "Symbol name (e.g. MyViewModel, fetchUserData, UserRecord)."),
                "maxResults": JSONSchema(type: "integer", description: "Maximum number of call sites to return (default: 50).")
            ],
            required: ["symbol"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let symbol = input["symbol"] as? String, !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: symbol")
        }
        let maxResults = (input["maxResults"] as? Int) ?? 50

        let root = context.workspaceRoot
        var matches: [(file: String, line: Int, content: String, isDeclaration: Bool)] = []

        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            guard text.contains(symbol) else { continue }

            let relPath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            let lines = text.components(separatedBy: .newlines)

            for (idx, line) in lines.enumerated() {
                if line.contains(symbol) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let isDecl = trimmed.hasPrefix("func \(symbol)") ||
                                 trimmed.hasPrefix("class \(symbol)") ||
                                 trimmed.hasPrefix("struct \(symbol)") ||
                                 trimmed.hasPrefix("enum \(symbol)") ||
                                 trimmed.hasPrefix("protocol \(symbol)") ||
                                 trimmed.hasPrefix("actor \(symbol)") ||
                                 trimmed.hasPrefix("var \(symbol)") ||
                                 trimmed.hasPrefix("let \(symbol)")

                    matches.append((file: relPath, line: idx + 1, content: trimmed, isDeclaration: isDecl))
                    if matches.count >= maxResults { break }
                }
            }
            if matches.count >= maxResults { break }
        }

        if matches.isEmpty {
            return .success("No references found for symbol '\(symbol)' in workspace.")
        }

        var report = "### Symbol Reference Graph for `\(symbol)` (\(matches.count) sites found):\n\n"
        let declarations = matches.filter { $0.isDeclaration }
        let usages = matches.filter { !$0.isDeclaration }

        if !declarations.isEmpty {
            report += "#### Declarations:\n"
            for d in declarations {
                report += "- `\(d.file):\(d.line)` → `\(d.content)`\n"
            }
            report += "\n"
        }

        report += "#### Usages & Call Sites:\n"
        for u in usages.prefix(40) {
            report += "- `\(u.file):\(u.line)` → `\(u.content)`\n"
        }

        return .success(report)
    }
}
