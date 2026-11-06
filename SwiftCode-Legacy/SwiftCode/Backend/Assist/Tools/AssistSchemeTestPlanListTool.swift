import Foundation

public struct AssistSchemeTestPlanListTool: AssistTool {
    public let id = "scheme_test_plan_list"
    public let name = "Scheme Test Plan List"
    public let description = "Finds .xctestplan files in the workspace and lists the test targets each plan covers."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Lists test plans.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        var plans: [String] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return .failure("Cannot enumerate workspace.")
        }
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "xctestplan" { plans.append(url.path) }
        }
        if plans.isEmpty {
            return .success("No .xctestplan files found in the workspace.", data: ["count": "0"])
        }
        var lines = ["Test plans (\(plans.count)):"]
        for path in plans.sorted() {
            let rel = AssistWorkspacePaths.relative(URL(fileURLWithPath: path), workspaceRoot: root)
            var detail = ""
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let targets = json["testTargets"] as? [[String: Any]] {
                let names = targets.compactMap { $0["target"] as? [String: Any] }.compactMap { $0["name"] as? String }
                detail = names.isEmpty ? "" : " — targets: " + names.joined(separator: ", ")
            }
            lines.append("- \(rel)\(detail)")
        }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(plans.count)"])
    }
}
