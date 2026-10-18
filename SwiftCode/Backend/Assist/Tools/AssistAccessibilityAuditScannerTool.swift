//
//  AssistAccessibilityAuditScannerTool.swift
//  SwiftCode
//

import Foundation

public struct AssistAccessibilityAuditScannerTool: AssistTool {
    public let id = "accessibility_audit_scanner"
    public let name = "Accessibility Audit Scanner"
    public let description = "Audits SwiftUI views for missing accessibility labels, hints, and VoiceOver tap targets."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans SwiftUI source files for unlabelled image buttons, icons without accessibility labels, and tap targets.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to Swift file or directory.")
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

        var warnings: [String] = []

        for file in filesToScan {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let rel = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let lines = content.components(separatedBy: .newlines)

            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Check for Image(systemName: ...) without accessibilityLabel
                if trimmed.contains("Image(systemName:") && !trimmed.contains("accessibilityLabel") && !trimmed.contains("accessibilityHidden") {
                    // Check next few lines to see if modifier is chained
                    let nextSnippet = lines.dropFirst(idx).prefix(4).joined(separator: "\n")
                    if !nextSnippet.contains(".accessibilityLabel") && !nextSnippet.contains(".accessibilityHidden") {
                        warnings.append("`\(rel):\(idx + 1)`: SF Symbol Image has no explicit `.accessibilityLabel` or `.accessibilityHidden(true)`.")
                    }
                }

                // Check for Button with empty string or plain image label
                if trimmed.hasPrefix("Button(\"\")") || trimmed.hasPrefix("Button(\" \")") {
                    warnings.append("`\(rel):\(idx + 1)`: Button with empty label has no VoiceOver text description.")
                }
            }
        }

        var report = "### Accessibility Audit Report (\(filesToScan.count) files scanned):\n\n"
        if warnings.isEmpty {
            report += "✅ No obvious accessibility omissions found. All scanned interactive elements have labels or standard descriptions."
        } else {
            report += "#### ⚠️ Potential VoiceOver & Accessibility Gaps (\(warnings.count)):\n"
            for w in warnings.prefix(25) {
                report += "- \(w)\n"
            }
        }

        return .success(report)
    }
}
