import Foundation

public struct AssistTargetDependenciesListTool: AssistTool {
    public let id = "target_dependencies_list"
    public let name = "Target Dependencies List"
    public let description = "Lists Xcode target-to-target dependencies parsed from the project's .pbxproj."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Lists target dependencies.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        guard let pbxproj = AssistWorkspaceScan.findPbxproj(in: root),
              let text = try? String(contentsOf: pbxproj, encoding: .utf8) else {
            return .failure("No .pbxproj found in the workspace.")
        }
        var targetNames: [String: String] = [:]
        if let p = try? NSRegularExpression(pattern: #"([0-9A-F]{24}) /\* (.+?) \*/ = \{\s*isa = PBXNativeTarget;"#) {
            for m in p.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) {
                    targetNames[String(text[r1])] = String(text[r2])
                }
            }
        }
        if targetNames.isEmpty {
            return .failure("No PBXNativeTarget entries parsed from the pbxproj.")
        }
        var depToTarget: [String: String] = [:]
        if let p = try? NSRegularExpression(pattern: #"([0-9A-F]{24}) /\* PBXTargetDependency \*/ = \{[^}]*?target = ([0-9A-F]{24})"#) {
            for m in p.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) {
                    depToTarget[String(text[r1])] = String(text[r2])
                }
            }
        }
        var lines = ["Target dependencies:"]
        var edgeCount = 0
        if let bp = try? NSRegularExpression(
            pattern: #"([0-9A-F]{24}) /\* (.+?) \*/ = \{\s*isa = PBXNativeTarget;.*?dependencies = \((.*?)\); "#,
            options: [.dotMatchesLineSeparators]
        ),
           let ip = try? NSRegularExpression(pattern: #"([0-9A-F]{24}) /\* PBXTargetDependency \*/"#) {
            for m in bp.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let nr = Range(m.range(at: 2), in: text), let dr = Range(m.range(at: 3), in: text) else { continue }
                let name = String(text[nr])
                let depBlock = String(text[dr])
                let depIDs = ip.matches(in: depBlock, range: NSRange(depBlock.startIndex..., in: depBlock)).compactMap { dm -> String? in
                    guard let r = Range(dm.range(at: 1), in: depBlock) else { return nil }
                    return String(depBlock[r])
                }
                let depNames = depIDs.compactMap { depToTarget[$0] }.compactMap { targetNames[$0] }.sorted()
                edgeCount += depNames.count
                lines.append("- \(name): \(depNames.isEmpty ? "(no target dependencies)" : depNames.joined(separator: ", "))")
            }
        }
        return .success(lines.joined(separator: "\n"), data: [
            "targetCount": "\(targetNames.count)", "edgeCount": "\(edgeCount)"
        ])
    }
}
