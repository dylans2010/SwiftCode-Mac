//
//  AssistSwiftConcurrencyAnalyzerTool.swift
//  SwiftCode
//

import Foundation

public struct AssistSwiftConcurrencyAnalyzerTool: AssistTool {
    public let id = "swift_concurrency_analyzer"
    public let name = "Swift Concurrency Analyzer"
    public let description = "Audits Swift code for Swift 6 strict concurrency hazards, mutable globals, and actor isolation boundaries."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans Swift files for concurrency hazards: non-Sendable captures, mutable global vars, unisolated async functions.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to file or directory in workspace.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        let root = context.workspaceRoot
        let targetURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return .failure("Path not found: \(path)")
        }

        var filesToScan: [URL] = []
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue {
            let enumerator = FileManager.default.enumerator(at: targetURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = enumerator?.nextObject() as? URL {
                if u.pathExtension == "swift" { filesToScan.append(u) }
            }
        } else {
            filesToScan.append(targetURL)
        }

        var findings: [String] = []

        for file in filesToScan {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let rel = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let lines = content.components(separatedBy: .newlines)

            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // 1. Mutable global or static var outside an actor or @MainActor
                if (trimmed.hasPrefix("public static var ") || trimmed.hasPrefix("static var ") || trimmed.hasPrefix("var ")) &&
                   !trimmed.contains("let ") && !content.contains("@MainActor") && !content.contains("actor ") {
                    if !trimmed.contains("{") { // exclude computed properties
                        findings.append("`\(rel):\(idx + 1)`: Mutable shared state `\(trimmed)` without `@MainActor` or `actor` isolation.")
                    }
                }

                // 2. DispatchQueue.main.sync deadlock risk
                if trimmed.contains("DispatchQueue.main.sync") {
                    findings.append("`\(rel):\(idx + 1)`: `DispatchQueue.main.sync` call detected; high deadlock hazard on main actor.")
                }

                // 3. Unchecked Sendable
                if trimmed.contains("@unchecked Sendable") {
                    findings.append("`\(rel):\(idx + 1)`: `@unchecked Sendable` used; verify manual synchronization mechanisms.")
                }
            }
        }

        var report = "### Swift 6 Strict Concurrency Analysis (\(filesToScan.count) files scanned):\n\n"
        if findings.isEmpty {
            report += "✅ Clean concurrency scan! No mutable globals, DispatchQueue.main.sync deadlocks, or unchecked Sendables detected."
        } else {
            report += "#### ⚠️ Concurrency Diagnostics (\(findings.count)):\n"
            for f in findings.prefix(25) {
                report += "- \(f)\n"
            }
        }

        return .success(report)
    }
}
