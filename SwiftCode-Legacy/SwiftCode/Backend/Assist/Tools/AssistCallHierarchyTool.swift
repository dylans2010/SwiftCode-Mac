import Foundation

public struct AssistCallHierarchyTool: AssistTool {
    public let id = "call_hierarchy"
    public let name = "Call Hierarchy"
    public let description = "For a function name, finds its definition site, its callers across the workspace, and the functions it calls."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Builds a call hierarchy for a function.",
            properties: [
                "function": JSONSchema(type: "string", description: "Function name to analyze (without parameters).")
            ],
            required: ["function"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let fn = (input["function"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !fn.isEmpty else {
            return .failure("Missing required parameter: function")
        }
        let root = context.workspaceRoot
        let files = AssistWorkspaceScan.swiftFiles(under: root)
        var definitions: [String] = []
        var callers: [String] = []
        var callees: Set<String> = []
        let callPattern = try? NSRegularExpression(pattern: #"(?<![\w.])"# + NSRegularExpression.escapedPattern(for: fn) + #"\s*\("#)
        let calleePattern = try? NSRegularExpression(pattern: #"(?<![\w.])([A-Za-z_][\w]*)\s*\("#)
        for url in files {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for (i, line) in lines.enumerated() {
                if let decl = AssistWorkspaceScan.declaredFuncName(line), decl == fn {
                    definitions.append("\(rel):\(i + 1)")
                    var depth = line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                    var j = i + 1
                    while j < lines.count && j < i + 400 && depth > 0 {
                        depth += lines[j].filter { $0 == "{" }.count - lines[j].filter { $0 == "}" }.count
                        let matches = calleePattern?.matches(in: lines[j], range: NSRange(lines[j].startIndex..., in: lines[j])).compactMap { m -> String? in
                            guard let r = Range(m.range(at: 1), in: lines[j]) else { return nil }
                            return String(lines[j][r])
                        } ?? []
                        for m in matches where m != fn { callees.insert(m) }
                        j += 1
                    }
                } else if let p = callPattern,
                          p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil,
                          AssistWorkspaceScan.declaredFuncName(line) == nil {
                    callers.append("\(rel):\(i + 1)")
                }
            }
        }
        if definitions.isEmpty && callers.isEmpty {
            return .success("No definition or callers found for function '\(fn)'.", data: ["function": fn, "definitionCount": "0", "callerCount": "0"])
        }
        var lines = ["Call hierarchy for '\(fn)':", "Definitions (\(definitions.count)):"]
        lines += definitions.prefix(20).map { "- \($0)" }
        lines.append("Callers (\(callers.count)):")
        lines += callers.prefix(50).map { "- \($0)" }
        if callers.count > 50 { lines.append("… [truncated: showing 50 of \(callers.count)]") }
        lines.append("Callees (\(callees.count) distinct):")
        lines += callees.sorted().prefix(50).map { "- \($0)" }
        return .success(lines.joined(separator: "\n"), data: [
            "function": fn,
            "definitionCount": "\(definitions.count)",
            "callerCount": "\(callers.count)",
            "calleeCount": "\(callees.count)"
        ])
    }
}
