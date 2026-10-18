import Foundation

public struct AssistAccessibilityAuditTool: AssistTool {
    public let id = "accessibility_audit"
    public let name = "Accessibility Audit"
    public let description = "Heuristic SwiftUI accessibility audit: flags Button/Image without accessibility labels, TextField with empty labels, and color-only state."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits SwiftUI files under path (workspace-relative, optional; defaults to workspace root). Findings are heuristics, not certainties.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative directory or file to audit (optional).")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let scanRoot: URL
        if let rawPath = input["path"] as? String, !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolved = resolveInsideWorkspace(rawPath, workspaceRoot: context.workspaceRoot) else {
                return .failure("Invalid path: '\(rawPath)' must be a workspace-relative path without '..' and must stay inside the workspace.")
            }
            scanRoot = resolved
        } else {
            scanRoot = context.workspaceRoot
        }

        let swiftFiles = listSwiftFiles(under: scanRoot)
        var findings: [String] = []
        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relative = relativePath(for: fileURL, workspaceRoot: context.workspaceRoot)
            findings.append(contentsOf: auditFile(content: content, relativePath: relative))
        }

        let sorted = findings.sorted()
        var output = "Accessibility audit: \(sorted.count) finding(s) in \(swiftFiles.count) Swift file(s). Findings are heuristics; verify each one."
        if sorted.isEmpty {
            output += " No issues detected."
        } else {
            output += "\n" + sorted.joined(separator: "\n")
        }
        return .success(output, data: [
            "finding_count": "\(sorted.count)",
            "files_scanned": "\(swiftFiles.count)"
        ])
    }

    private func auditFile(content: String, relativePath: String) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var findings: [String] = []
        var pendingButtonLine: Int?
        var pendingButtonDeadline = 0
        var pendingImageLine: Int?
        var pendingImageDeadline = 0

        func flushButton(upTo index: Int) {
            if let line = pendingButtonLine, index > pendingButtonDeadline {
                findings.append("\(relativePath):\(line):Button without .accessibilityLabel (heuristic)")
                pendingButtonLine = nil
            }
        }
        func flushImage(upTo index: Int) {
            if let line = pendingImageLine, index > pendingImageDeadline {
                findings.append("\(relativePath):\(line):Image without .accessibilityLabel / .accessibilityHidden (heuristic)")
                pendingImageLine = nil
            }
        }

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine
            flushButton(upTo: lineNumber)
            flushImage(upTo: lineNumber)
            let hasA11y = line.contains("accessibilityLabel") || line.contains("accessibilityHidden") || line.contains("accessibilityElement")
            if hasA11y {
                pendingButtonLine = nil
                pendingImageLine = nil
            }
            if line.contains("Button(") {
                if !hasA11y {
                    if pendingButtonLine != nil {
                        flushButton(upTo: pendingButtonDeadline + 1)
                    }
                    pendingButtonLine = lineNumber
                    pendingButtonDeadline = lineNumber + 10
                }
            }
            if line.contains("Image(") {
                if !hasA11y {
                    if pendingImageLine != nil {
                        flushImage(upTo: pendingImageDeadline + 1)
                    }
                    pendingImageLine = lineNumber
                    pendingImageDeadline = lineNumber + 5
                }
            }
            if line.contains("TextField(") && line.contains("\"\"") {
                findings.append("\(relativePath):\(lineNumber):TextField with empty label (heuristic)")
            }
            if line.contains("foregroundColor") && (line.contains(".red") || line.contains(".green") || line.contains(".orange")) && !hasA11y {
                findings.append("\(relativePath):\(lineNumber):Color-only state via foregroundColor (heuristic) - pair with a label or icon")
            }
        }
        flushButton(upTo: lines.count + 100)
        flushImage(upTo: lines.count + 100)
        return findings
    }

    private func listSwiftFiles(under root: URL) -> [URL] {
        var found: [URL] = []
        let skipped = Set([".git", "DerivedData", ".build", "Pods", "node_modules", ".swiftpm", "Carthage", "vendor"])
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), !isDir.boolValue {
            return root.pathExtension == "swift" ? [root] : []
        }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return found
        }
        for case let url as URL in enumerator {
            var itemIsDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &itemIsDir), itemIsDir.boolValue {
                if skipped.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension == "swift" {
                found.append(url)
            }
        }
        return found.sorted(by: { $0.path < $1.path })
    }

    private func resolveInsideWorkspace(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(separator: "/").map(String.init)
        if components.contains("..") { return nil }
        if trimmed.hasPrefix("/") {
            guard trimmed == workspaceRoot.path || trimmed.hasPrefix(workspaceRoot.path + "/") else { return nil }
            return URL(fileURLWithPath: trimmed)
        }
        return workspaceRoot.appendingPathComponent(trimmed)
    }

    private func relativePath(for url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.path
        if url.path == root { return "." }
        if url.path.hasPrefix(root + "/") {
            return String(url.path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }
}
