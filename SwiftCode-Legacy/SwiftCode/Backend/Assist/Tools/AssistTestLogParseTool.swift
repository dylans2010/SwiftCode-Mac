import Foundation

public struct AssistTestLogParseTool: AssistTool {
    public let id = "test_log_parse"
    public let name = "Parse Test Log"
    public let description = "Parses a test log for passed/failed test cases, suite summaries, and errors, returning counts plus the failed test list."

    public init() {}

    public var capability: ToolCapability { .testing }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Parses a test log file inside the workspace.",
            properties: [
                "logPath": JSONSchema(type: "string", description: "Required. Workspace-relative path to a test log file.")
            ],
            required: ["logPath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let logPath = (input["logPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !logPath.isEmpty else {
            return .failure("Missing required parameter: logPath")
        }
        guard let resolved = resolveInsideWorkspace(logPath, workspaceRoot: context.workspaceRoot) else {
            return .failure("logPath must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return .failure("Log file not found at '\(logPath)'.")
        }
        guard let content = try? String(contentsOf: resolved, encoding: .utf8) else {
            return .failure("Could not read log file at '\(logPath)' as UTF-8 text.")
        }
        var passed = 0
        var failed = 0
        var failedTests: [String] = []
        var suiteLines: [String] = []
        var errorLines: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.contains("Test Case") {
                let isPassed = line.contains(" passed")
                let isFailed = line.contains(" failed")
                if isPassed && !isFailed {
                    passed += 1
                } else if isFailed && !isPassed {
                    failed += 1
                    if let name = extractTestName(from: line), !failedTests.contains(name) {
                        failedTests.append(name)
                    }
                }
            }
            if line.contains("Test Suite") && (line.contains("passed") || line.contains("failed")) {
                suiteLines.append(line)
            }
            if line.contains(": error:") || line.hasPrefix("error:") {
                errorLines.append(line)
            }
        }
        let total = passed + failed
        var output = "Test log '\(logPath)': \(total) test case(s), \(passed) passed, \(failed) failed, \(errorLines.count) error line(s)."
        if !failedTests.isEmpty {
            output += "\nFailed tests:\n" + failedTests.map { "- \($0)" }.joined(separator: "\n")
        }
        if !suiteLines.isEmpty {
            output += "\nSuite summaries:\n" + suiteLines.prefix(10).joined(separator: "\n")
        }
        if !errorLines.isEmpty {
            output += "\nErrors:\n" + errorLines.prefix(10).joined(separator: "\n")
        }
        return .success(output, data: [
            "total": "\(total)",
            "passed": "\(passed)",
            "failed": "\(failed)",
            "errorCount": "\(errorLines.count)",
            "failedTests": failedTests.joined(separator: ",")
        ])
    }

    private func extractTestName(from line: String) -> String? {
        if let start = line.range(of: "Test Case '"),
           let end = line.range(of: "'", options: [], range: start.upperBound..<line.endIndex) {
            let name = String(line[start.upperBound..<end.lowerBound])
            if !name.isEmpty { return name }
        }
        if let bracketStart = line.range(of: "-["),
           let bracketEnd = line.range(of: "]", options: [], range: bracketStart.upperBound..<line.endIndex) {
            let name = String(line[bracketStart.upperBound..<bracketEnd.lowerBound])
            if !name.isEmpty { return name }
        }
        return nil
    }

    private func resolveInsideWorkspace(_ rawPath: String, workspaceRoot: URL) -> URL? {
        if rawPath.isEmpty { return nil }
        if rawPath.components(separatedBy: "/").contains("..") { return nil }
        let root = workspaceRoot.standardized
        let candidate: URL
        if rawPath.hasPrefix("/") {
            candidate = URL(fileURLWithPath: rawPath).standardized
        } else {
            candidate = root.appendingPathComponent(rawPath).standardized
        }
        let rootPath = root.path
        if candidate.path == rootPath { return candidate }
        if candidate.path.hasPrefix(rootPath + "/") { return candidate }
        return nil
    }
}
