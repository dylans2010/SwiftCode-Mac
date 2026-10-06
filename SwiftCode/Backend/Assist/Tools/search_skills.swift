//
//  search_skills.swift
//  SwiftCode
//
//  Real native Assist tool for querying SwiftCode's authoritative local skills library.
//

import Foundation

@MainActor
public final class SearchSkillsTool: AssistTool {
    public let id = "search_skills"
    public let name = "Search Agent Skills"
    public let description = "Search SwiftCode's authoritative local skills library for specialized domain guides, architectures, workflows, and best practices. Call this tool when an objective involves a specific technology, framework, pattern, or task category."

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Search indexed skills in the local SwiftCode skills repository.",
            properties: [
                "query": JSONSchema(
                    type: "string",
                    description: "Search keywords or task intent (e.g. 'SwiftUI architecture', 'TypeScript testing', 'Core Data', 'security audit')."
                ),
                "limit": JSONSchema(
                    type: "integer",
                    description: "Maximum number of matching skills to return (default: 8, max: 20)."
                )
            ],
            required: ["query"]
        )
    }

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let query = input["query"] as? String, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter 'query'.")
        }

        let limit = min(20, max(1, input["limit"] as? Int ?? 8))
        let matches = SkillIndex.shared.search(query: query, limit: limit)

        if matches.isEmpty {
            return .success("No skills found matching query '\(query)'. You can continue executing the task using standard engineering principles.")
        }

        var output = "### Discovered Skills Matching '\(query)' (\(matches.count) results):\n\n"
        for (idx, skill) in matches.enumerated() {
            output += "\(idx + 1). **\(skill.name)** (`\(skill.id)`)\n"
            output += "   - **Source**: \(skill.sourceKind.rawValue) (\(skill.sourceDescription))\n"
            output += "   - **Location**: `\(skill.path)`\n"
            output += "   - **Description**: \(skill.description)\n"
            if !skill.tags.isEmpty {
                output += "   - **Tags**: \(skill.tags.joined(separator: ", "))\n"
            }
            if !skill.recommendedTools.isEmpty {
                output += "   - **Tools**: \(skill.recommendedTools.joined(separator: ", "))\n"
            }
            output += "   - *To follow this skill, inspect instructions using `read_file` on `\(skill.path)`.*\n\n"
        }

        output += "\n> **Guidance**: Inspect the most relevant skill above using `read_file` if detailed execution instructions or rules are needed."

        return .success(output)
    }
}
