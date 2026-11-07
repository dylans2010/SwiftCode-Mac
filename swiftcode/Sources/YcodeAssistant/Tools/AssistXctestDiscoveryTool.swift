import Foundation

public struct AssistXctestDiscoveryTool: AssistTool {
    public let id = "xctest_discovery"
    public let name = "XCTest Discovery"
    public let description = "Discovers XCTestCase subclasses and their test methods across the workspace — a test inventory without running anything."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Discovers XCTest cases.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let classPattern = try? NSRegularExpression(pattern: #"class\s+([A-Za-z_][\w]*)\s*:\s*XCTestCase"#)
        let methodPattern = try? NSRegularExpression(pattern: #"func\s+(test[A-Za-z_][\w]*)\s*\("#)
        var classes: [(String, String, Int)] = []
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            var currentClass: String?
            var currentCount = 0
            var classLine = 0
            for (i, line) in lines.enumerated() {
                if let m = classPattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let r = Range(m.range(at: 1), in: line) {
                    if let cc = currentClass { classes.append((cc, rel, currentCount)) }
                    currentClass = String(line[r])
                    currentCount = 0
                    classLine = i + 1
                } else if currentClass != nil,
                          methodPattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    currentCount += 1
                }
                _ = classLine
            }
            if let cc = currentClass { classes.append((cc, rel, currentCount)) }
        }
        if classes.isEmpty {
            return .success("No XCTestCase subclasses found in the workspace.", data: ["classCount": "0", "testCount": "0"])
        }
        let totalTests = classes.reduce(0) { $0 + $1.2 }
        var lines = ["XCTest inventory: \(classes.count) test classes, \(totalTests) test methods:"]
        for (name, rel, count) in classes.sorted(by: { $0.0 < $1.0 }) {
            lines.append("- \(name) — \(rel) (\(count) tests)")
        }
        return .success(lines.joined(separator: "\n"), data: [
            "classCount": "\(classes.count)", "testCount": "\(totalTests)"
        ])
    }
}
