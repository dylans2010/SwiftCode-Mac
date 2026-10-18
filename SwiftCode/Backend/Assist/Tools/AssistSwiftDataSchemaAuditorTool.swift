//
//  AssistSwiftDataSchemaAuditorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistSwiftDataSchemaAuditorTool: AssistTool {
    public let id = "swift_data_schema_auditor"
    public let name = "SwiftData Schema Auditor"
    public let description = "Audits SwiftData models (@Model), attributes, relationships, and migration schemas across the workspace."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans the codebase for SwiftData @Model definitions, @Attribute constraints, and @Relationship macros.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional directory path to scan. Defaults to workspace root.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        var models: [(name: String, file: String, line: Int, properties: [String])] = []

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            guard text.contains("@Model") else { continue }

            let relPath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            let lines = text.components(separatedBy: .newlines)

            var isNextClass = false
            var currentModelName = ""
            var currentLine = 0
            var currentProps: [String] = []

            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("@Model") {
                    isNextClass = true
                } else if isNextClass && (trimmed.hasPrefix("class ") || trimmed.hasPrefix("final class ") || trimmed.hasPrefix("public class ")) {
                    let parts = trimmed.components(separatedBy: .whitespaces)
                    if let cIdx = parts.firstIndex(of: "class"), cIdx + 1 < parts.count {
                        currentModelName = parts[cIdx + 1].components(separatedBy: ":").first ?? "Unknown"
                        currentLine = idx + 1
                        currentProps = []
                        isNextClass = false
                    }
                } else if !currentModelName.isEmpty {
                    if trimmed.hasPrefix("var ") || trimmed.hasPrefix("@Attribute") || trimmed.hasPrefix("@Relationship") {
                        currentProps.append(trimmed)
                    } else if trimmed == "}" {
                        models.append((name: currentModelName, file: relPath, line: currentLine, properties: currentProps))
                        currentModelName = ""
                    }
                }
            }
        }

        if models.isEmpty {
            return .success("No SwiftData `@Model` classes discovered in the workspace.")
        }

        var report = "### Discovered SwiftData Models (\(models.count) found):\n\n"
        for m in models {
            report += "#### `@Model class \(m.name)` (`\(m.file):\(m.line)`):\n"
            if m.properties.isEmpty {
                report += "  _(No explicit stored var properties detected)_\n"
            } else {
                for p in m.properties.prefix(12) {
                    report += "  - `\(p)`\n"
                }
            }
            report += "\n"
        }

        return .success(report)
    }
}
