import Foundation

public struct AssistBuildConfigurationListTool: AssistTool {
    public let id = "build_configuration_list"
    public let name = "Build Configuration List"
    public let description = "Lists build configurations (Debug/Release/custom) for the project and each target from the .pbxproj."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Lists build configurations.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        guard let pbxproj = AssistWorkspaceScan.findPbxproj(in: root),
              let text = try? String(contentsOf: pbxproj, encoding: .utf8) else {
            return .failure("No .pbxproj found in the workspace.")
        }
        // Map each XCConfigurationList to its configurations, then resolve owners.
        var lines = ["Build configurations:"]
        var configNames: Set<String> = []
        // Find configuration lists and their buildConfigurations entries.
        guard let listPattern = try? NSRegularExpression(
            pattern: #"([0-9A-F]{24}) /\* Build configuration list for (PBXProject|PBXNativeTarget) "([^"]+)" \*/ = \{\s*isa = XCConfigurationList;.*?buildConfigurations = \((.*?)\);"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            return .failure("Internal regex error.")
        }
        let lists = listPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        // Map configuration id -> name.
        var configIdToName: [String: String] = [:]
        if let cp = try? NSRegularExpression(pattern: #"([0-9A-F]{24}) /\* ([^*]+?) \*/ = \{\s*isa = XCBuildConfiguration;"#) {
            for m in cp.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) {
                    configIdToName[String(text[r1])] = String(text[r2]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        let idPattern = try? NSRegularExpression(pattern: #"([0-9A-F]{24})"#)
        for m in lists {
            guard let ownerRange = Range(m.range(at: 3), in: text),
                  let configsRange = Range(m.range(at: 4), in: text) else { continue }
            let owner = String(text[ownerRange])
            let block = String(text[configsRange])
            let ids = idPattern?.matches(in: block, range: NSRange(block.startIndex..., in: block)).compactMap { dm -> String? in
                guard let r = Range(dm.range(at: 1), in: block) else { return nil }
                return String(block[r])
            } ?? []
            let names = ids.compactMap { configIdToName[$0] }.sorted()
            names.forEach { configNames.insert($0) }
            lines.append("- \(owner): \(names.isEmpty ? "(none parsed)" : names.joined(separator: ", "))")
        }
        if lists.isEmpty {
            return .failure("No configuration lists parsed from the pbxproj.")
        }
        return .success(lines.joined(separator: "\n"), data: [
            "ownerCount": "\(lists.count)", "configurations": configNames.sorted().joined(separator: ",")
        ])
    }
}
