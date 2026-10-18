import Foundation

public struct AssistBuildPhaseScriptsListTool: AssistTool {
    public let id = "build_phase_scripts_list"
    public let name = "Build Phase Scripts List"
    public let description = "Lists Run Script build phases from the .pbxproj with their names and script bodies (truncated)."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Lists build-phase scripts.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        guard let pbxproj = AssistWorkspaceScan.findPbxproj(in: root),
              let text = try? String(contentsOf: pbxproj, encoding: .utf8) else {
            return .failure("No .pbxproj found in the workspace.")
        }
        guard let p = try? NSRegularExpression(
            pattern: #"/\* (.+?) \*/ = \{\s*isa = PBXShellScriptBuildPhase;.*?name = (.+?);.*?shellScript = "(.*?)";"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            return .failure("Internal regex error.")
        }
        let matches = p.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if matches.isEmpty {
            return .success("No Run Script build phases found.", data: ["count": "0"])
        }
        var lines = ["Run Script build phases (\(matches.count)):"]
        for m in matches {
            guard let cr = Range(m.range(at: 1), in: text),
                  let nr = Range(m.range(at: 2), in: text),
                  let sr = Range(m.range(at: 3), in: text) else { continue }
            let name = String(text[nr]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let script = String(text[sr]).replacingOccurrences(of: "\\n", with: "\n")
            let (preview, wasTruncated) = AssistTextFormat.truncated(script, limit: 600, label: "script truncated")
            lines.append("- \(String(text[cr])) (phase: \(name)):")
            lines.append("```sh\n\(preview)\n```" + (wasTruncated ? " [truncated]" : ""))
        }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(matches.count)"])
    }
}
