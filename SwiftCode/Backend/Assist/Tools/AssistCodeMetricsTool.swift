import Foundation

public struct AssistCodeMetricsTool: AssistTool {
    public let id = "code_metrics_analyzer"
    public let name = "Code Metrics Analyzer"
    public let description = "Calculates lines of code, comment density, type counts, and complexity metrics for Swift source files."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Analyze code metrics and structure of Swift files in the workspace.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to a Swift file or directory.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        let targetURL = context.workspaceRoot.appendingPathComponent(path)
        let fileManager = FileManager.default

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            return .failure("File or directory not found at: \(path)")
        }

        var filesToAnalyze: [URL] = []
        if isDir.boolValue {
            if let enumerator = fileManager.enumerator(at: targetURL, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" {
                        filesToAnalyze.append(fileURL)
                    }
                }
            }
        } else {
            if targetURL.pathExtension == "swift" {
                filesToAnalyze.append(targetURL)
            } else {
                return .failure("Target is not a Swift source file: \(path)")
            }
        }

        guard !filesToAnalyze.isEmpty else {
            return .failure("No Swift files found to analyze under: \(path)")
        }

        var totalLines = 0
        var totalBlank = 0
        var totalComments = 0
        var totalFunctions = 0
        var totalTypes = 0
        var totalBranches = 0

        for fileURL in filesToAnalyze {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            totalLines += lines.count

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    totalBlank += 1
                } else if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                    totalComments += 1
                } else {
                    if trimmed.contains("func ") { totalFunctions += 1 }
                    if trimmed.contains("struct ") || trimmed.contains("class ") || trimmed.contains("enum ") || trimmed.contains("actor ") {
                        totalTypes += 1
                    }
                    if trimmed.contains("if ") || trimmed.contains("guard ") || trimmed.contains("for ") || trimmed.contains("while ") || trimmed.contains("case ") {
                        totalBranches += 1
                    }
                }
            }
        }

        let codeLines = totalLines - totalBlank - totalComments
        let commentRatio = codeLines > 0 ? Double(totalComments) / Double(codeLines) * 100.0 : 0.0
        let cyclomaticEst = totalFunctions > 0 ? (Double(totalBranches) / Double(totalFunctions)) + 1.0 : 1.0

        let output = """
        Code Metrics for '\(path)' (\(filesToAnalyze.count) Swift files):
        - Total Lines: \(totalLines)
        - Code Lines: \(codeLines)
        - Blank Lines: \(totalBlank)
        - Comment Lines: \(totalComments) (\(String(format: "%.1f", commentRatio))% comment ratio)
        - Declared Types (struct/class/enum/actor): \(totalTypes)
        - Functions: \(totalFunctions)
        - Decision Branches (if/guard/for/while/case): \(totalBranches)
        - Avg Cyclomatic Complexity per Function: ~\(String(format: "%.1f", cyclomaticEst))
        """

        return .success(output)
    }
}
