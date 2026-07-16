import Foundation

public struct AssistAutonomousReviewEngine: AssistTool {
    public let id = "autonomous_review_engine"
    public let name = "Autonomous Review Engine"
    public let description = "Performs static self-review, detects inefficient patterns, and proposes refactors."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = AssistToolingSupport.resolvePath(input["path"] as? String, workspaceRoot: context.workspaceRoot)
        let files = AssistToolingSupport.enumeratedFiles(at: root, allowedExtensions: ["swift"], maxFileSize: 800_000)
        var findings: [String] = []

        for file in files {
            guard let text = AssistToolingSupport.readText(file) else { continue }
            let rel = AssistToolingSupport.relativePath(for: file, workspaceRoot: context.workspaceRoot)
            if text.contains("!\n") || text.contains(" as!") {
                findings.append("\(rel): force-unwrap/type-cast usage detected; prefer safe optional binding.")
            }
            if text.contains("DispatchQueue.main.async") && text.contains("Task {") {
                findings.append("\(rel): mixed concurrency primitives found; consider consolidating around Swift Concurrency.")
            }
            if text.components(separatedBy: "for ").count > 6 && text.contains(".filter") == false {
                findings.append("\(rel): loop-heavy section; evaluate higher-order transformations or index precomputation.")
            }
        }

        return .success("Autonomous review complete.", data: ["finding_count": "\(findings.count)", "findings": findings.prefix(1000).joined(separator: "\n")])
    }
}
