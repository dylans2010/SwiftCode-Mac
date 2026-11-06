import Foundation

public struct AssistSecretsScanTool: AssistTool {
    public let id = "secrets_scan"
    public let name = "Secrets Scan"
    public let description = "Scans source and config files for secret patterns. Reports file:line:pattern only and never outputs matched secret values."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans for secret patterns under path (workspace-relative, optional; defaults to workspace root).",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative directory or file to scan (optional).")
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

        let patterns: [(label: String, pattern: String, options: NSRegularExpression.Options)] = [
            (label: "AWS Access Key ID", pattern: "AKIA[0-9A-Z]{16}", options: []),
            (label: "GitHub token", pattern: "ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}", options: []),
            (label: "OpenAI-style API key", pattern: "sk-[A-Za-z0-9]{20,}", options: []),
            (label: "api_key assignment", pattern: "api[_-]?key\\s*=\\s*['\"][^'\"]+['\"]", options: [.caseInsensitive]),
            (label: "password assignment", pattern: "password\\s*=\\s*['\"][^'\"]+['\"]", options: [.caseInsensitive]),
            (label: "Private key block", pattern: "-----BEGIN [^-]* PRIVATE KEY-----", options: [])
        ]
        var compiled: [(label: String, regex: NSRegularExpression)] = []
        for entry in patterns {
            do {
                let regex = try NSRegularExpression(pattern: entry.pattern, options: entry.options)
                compiled.append((label: entry.label, regex: regex))
            } catch {
                return .failure("Failed to compile secret pattern '\(entry.label)': \(error.localizedDescription)")
            }
        }

        let files = listScannableFiles(under: scanRoot)
        var findings: [String] = []
        var seen = Set<String>()
        var filesWithFindings = Set<String>()
        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relative = relativePath(for: fileURL, workspaceRoot: context.workspaceRoot)
            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                for entry in compiled {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if entry.regex.firstMatch(in: line, options: [], range: range) != nil {
                        // NEVER include the matched value or the line content.
                        let finding = "\(relative):\(index + 1):\(entry.label)"
                        if !seen.contains(finding) {
                            seen.insert(finding)
                            findings.append(finding)
                            filesWithFindings.insert(relative)
                        }
                    }
                }
            }
        }

        let sorted = findings.sorted()
        var output = "Secrets scan: \(sorted.count) finding(s) in \(filesWithFindings.count) file(s), \(files.count) file(s) scanned."
        if sorted.isEmpty {
            output += " No secret patterns found."
        } else {
            output += "\n" + sorted.joined(separator: "\n")
        }
        return .success(output, data: [
            "finding_count": "\(sorted.count)",
            "files_scanned": "\(files.count)",
            "files_with_findings": "\(filesWithFindings.count)"
        ])
    }

    private func listScannableFiles(under root: URL) -> [URL] {
        var found: [URL] = []
        let skippedDirs = Set([".git", "DerivedData", ".build", "Pods", "node_modules", ".swiftpm", "Carthage", "vendor", ".doccarchive"])
        let skippedExtensions = Set(["png", "jpg", "jpeg", "gif", "pdf", "zip", "a", "o", "dylib", "car", "icns", "mp3", "mp4", "mov", "sqlite", "db", "xcarchive", "framework", "app", "ipa"])
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), !isDir.boolValue {
            return [root]
        }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return found
        }
        for case let url as URL in enumerator {
            var itemIsDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &itemIsDir), itemIsDir.boolValue {
                if skippedDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if skippedExtensions.contains(url.pathExtension.lowercased()) { continue }
            found.append(url)
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
