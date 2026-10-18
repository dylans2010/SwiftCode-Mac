import Foundation

public struct AssistConcurrencyAuditTool: AssistTool {
    public let id = "concurrency_audit"
    public let name = "Concurrency Audit"
    public let description = "Heuristic scan for Swift concurrency hazards: DispatchQueue.main.sync, nonisolated(unsafe), mutable static vars, Task blocks without await, force unwraps inside async functions, and SwiftUI types without @MainActor. All findings are heuristic leads, not confirmed bugs."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans Swift files for concurrency hazards.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of a file or directory to audit. Defaults to the workspace root.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let root = resolvePath(input["path"] as? String, in: context) else {
            return .failure("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let files = enumerateSwiftFiles(at: root)
        if files.isEmpty {
            return .success(
                "Concurrency Audit: no Swift files found.",
                data: ["scannedFiles": "0", "findingCount": "0", "findings": ""]
            )
        }

        guard let staticVarRegex = try? NSRegularExpression(pattern: "\\bstatic\\s+var\\s+([A-Za-z_][A-Za-z0-9_]*)", options: []),
              let funcRegex = try? NSRegularExpression(pattern: "\\bfunc\\b", options: []) else {
            return .failure("Concurrency Audit: failed to build scan patterns.")
        }

        var findings: [(relative: String, line: Int, issue: String)] = []
        for url in files {
            guard let text = readFile(url) else { continue }
            let relative = relativePath(url, root: context.workspaceRoot)
            let lines = text.components(separatedBy: "\n")

            // File-level: SwiftUI types without @MainActor anywhere in the file.
            if text.contains("import SwiftUI") && !text.contains("@MainActor") {
                for (index, line) in lines.enumerated() where line.contains(": View") || line.contains(": ObservableObject") || line.contains(": App") {
                    findings.append((relative: relative, line: index + 1, issue: "SwiftUI type without @MainActor in file (heuristic — verify whether main-actor isolation is needed)"))
                    break
                }
            }

            var braceDepth = 0
            var inAsyncFunction = false
            var asyncDepth = 0
            var index = 0
            while index < lines.count {
                let line = lines[index]
                let lineNumber = index + 1
                let range = NSRange(line.startIndex..., in: line)

                if line.contains("DispatchQueue.main.sync") {
                    findings.append((relative: relative, line: lineNumber, issue: "DispatchQueue.main.sync can deadlock when called from the main thread (heuristic)"))
                }
                if line.contains("nonisolated(unsafe)") {
                    findings.append((relative: relative, line: lineNumber, issue: "nonisolated(unsafe) bypasses Swift concurrency safety (heuristic — verify the access is actually safe)"))
                }
                if let match = staticVarRegex.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges >= 2, let nameRange = Range(match.range(at: 1), in: line) {
                    findings.append((relative: relative, line: lineNumber, issue: "Mutable static var '\(String(line[nameRange]))' shared across threads (heuristic — verify synchronization)"))
                }

                // Track async function bodies by brace depth.
                if funcRegex.firstMatch(in: line, options: [], range: range) != nil && line.contains("async") && !inAsyncFunction {
                    inAsyncFunction = true
                    asyncDepth = braceDepth
                }

                // Task block without await: scan ahead up to 40 lines.
                if line.contains("Task") && line.contains("{") {
                    var innerDepth = 0
                    var sawBrace = false
                    var hasAwait = false
                    var cursor = index
                    while cursor < lines.count && cursor < index + 41 {
                        let inner = lines[cursor]
                        if inner.contains("await") { hasAwait = true }
                        innerDepth += inner.filter { $0 == "{" }.count - inner.filter { $0 == "}" }.count
                        if innerDepth > 0 { sawBrace = true }
                        if sawBrace && innerDepth <= 0 { break }
                        cursor += 1
                    }
                    if sawBrace && !hasAwait {
                        findings.append((relative: relative, line: lineNumber, issue: "Task block without await (heuristic — verify the block does not need to suspend)"))
                    }
                }

                if inAsyncFunction, hasForceUnwrap(line) {
                    findings.append((relative: relative, line: lineNumber, issue: "Force unwrap inside an async function (heuristic — a nil crash here aborts the task)"))
                }

                braceDepth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                if inAsyncFunction && braceDepth <= asyncDepth {
                    inAsyncFunction = false
                }
                index += 1
                if findings.count >= 500 { break }
            }
            if findings.count >= 500 { break }
        }

        let capped = Array(findings.prefix(500))
        var output = "Concurrency Audit (heuristic): scanned \(files.count) Swift file(s), found \(findings.count) finding(s).\n"
        if capped.isEmpty {
            output += "No concurrency hazards found."
        } else {
            output += capped.map { "\($0.relative):\($0.line): \($0.issue)" }.joined(separator: "\n")
            if findings.count > capped.count {
                output += "\n… and \(findings.count - capped.count) more finding(s) omitted (listing capped at 500)."
            }
        }
        return .success(
            output,
            data: [
                "scannedFiles": "\(files.count)",
                "findingCount": "\(findings.count)",
                "findings": capped.map { "\($0.relative):\($0.line): \($0.issue)" }.joined(separator: "\n")
            ]
        )
    }

    private func hasForceUnwrap(_ line: String) -> Bool {
        // A force unwrap is "!" preceded by a value character (letter, digit,
        // "_", ")", or "]") and not followed by "=" (which is "!=").
        let chars = Array(line)
        guard chars.count >= 2 else { return false }
        for index in 1..<chars.count {
            if chars[index] == "!" {
                let previous = chars[index - 1]
                let precededByValue = previous.isLetter || previous.isNumber || previous == "_" || previous == ")" || previous == "]"
                if precededByValue {
                    let next = index + 1 < chars.count ? chars[index + 1] : nil
                    if next != "=" {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func resolvePath(_ raw: String?, in context: AssistContext) -> URL? {
        let workspace = context.workspaceRoot.standardized
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return workspace }
        if raw.contains("..") { return nil }
        let candidate: URL
        if raw.hasPrefix("/") {
            candidate = URL(fileURLWithPath: raw).standardized
        } else {
            candidate = workspace.appendingPathComponent(raw).standardized
        }
        if candidate == workspace || candidate.path.hasPrefix(workspace.path + "/") {
            return candidate
        }
        return nil
    }

    private func enumerateSwiftFiles(at root: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            if root.pathExtension.lowercased() == "swift" && fileSize(root) <= 300_000 {
                return [root]
            }
            return []
        }
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return results }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if name == ".git" || name == "DerivedData" || name == ".build" || name == "Pods" || name == "node_modules" {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension.lowercased() != "swift" { continue }
            if fileSize(url) > 300_000 { continue }
            results.append(url)
            if results.count >= 5000 { break }
        }
        return results.sorted { $0.path < $1.path }
    }

    private func fileSize(_ url: URL) -> Int {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
            return size
        }
        return 0
    }

    private func readFile(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardized.path
        let path = url.standardized.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}
