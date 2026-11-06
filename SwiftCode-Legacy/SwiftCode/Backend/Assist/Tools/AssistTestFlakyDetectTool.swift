import Foundation

public struct AssistTestFlakyDetectTool: AssistTool {
    public let id = "test_flaky_detect"
    public let name = "Flaky Test Detection"
    public let description = "Parses test logs and reports tests that show both pass and fail outcomes across runs."

    public init() {}

    public var capability: ToolCapability { .testing }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Parses one test log file or all logs in a directory for flaky tests.",
            properties: [
                "logPath": JSONSchema(type: "string", description: "Workspace-relative path to a test log file."),
                "logsDir": JSONSchema(type: "string", description: "Workspace-relative path to a directory of test log files. Used when logPath is empty.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let logPath = (input["logPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let logsDir = (input["logsDir"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var logURLs: [URL] = []
        if !logPath.isEmpty {
            guard let resolved = resolveInsideWorkspace(logPath, workspaceRoot: context.workspaceRoot) else {
                return .failure("logPath must be inside the workspace and must not contain '..'.")
            }
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                return .failure("Log file not found at '\(logPath)'.")
            }
            logURLs = [resolved]
        } else if !logsDir.isEmpty {
            guard let resolvedDir = resolveInsideWorkspace(logsDir, workspaceRoot: context.workspaceRoot) else {
                return .failure("logsDir must be inside the workspace and must not contain '..'.")
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolvedDir.path, isDirectory: &isDir), isDir.boolValue else {
                return .failure("Logs directory not found at '\(logsDir)'.")
            }
            guard let contents = try? FileManager.default.contentsOfDirectory(at: resolvedDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                return .failure("Could not list logs directory at '\(logsDir)'.")
            }
            logURLs = contents.filter { ["log", "txt"].contains($0.pathExtension.lowercased()) }.sorted { $0.path < $1.path }
            if logURLs.isEmpty {
                return .failure("No .log or .txt files found in '\(logsDir)'.")
            }
        } else {
            return .failure("Provide logPath or logsDir.")
        }

        var passCounts: [String: Int] = [:]
        var failCounts: [String: Int] = [:]
        var filesRead = 0
        for url in logURLs {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            filesRead += 1
            for outcome in parseOutcomes(from: content) {
                if outcome.passed {
                    passCounts[outcome.test, default: 0] += 1
                } else {
                    failCounts[outcome.test, default: 0] += 1
                }
            }
        }
        let flaky = Set(passCounts.keys).intersection(Set(failCounts.keys)).sorted()
        let distinctCount = Set(passCounts.keys).union(Set(failCounts.keys)).count
        var output = "Flaky test scan across \(filesRead) log file(s): \(distinctCount) distinct tests observed, \(flaky.count) flaky."
        if flaky.isEmpty {
            output += "\nNo test showed both a pass and a fail."
        } else {
            for test in flaky {
                output += "\n- \(test): \(passCounts[test] ?? 0) pass, \(failCounts[test] ?? 0) fail"
            }
        }
        return .success(output, data: [
            "filesRead": "\(filesRead)",
            "flakyCount": "\(flaky.count)",
            "flakyTests": flaky.joined(separator: ",")
        ])
    }

    private struct TestOutcome {
        let test: String
        let passed: Bool
    }

    private func parseOutcomes(from content: String) -> [TestOutcome] {
        var results: [TestOutcome] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.contains("Test Case") else { continue }
            let isPassed = line.contains(" passed")
            let isFailed = line.contains(" failed")
            guard isPassed != isFailed else { continue }
            if let name = extractTestName(from: line) {
                results.append(TestOutcome(test: name, passed: isPassed))
            }
        }
        return results
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
