import Foundation

public struct AssistGitBlameTool: AssistTool {
    public let id = "git_blame"
    public let name = "Git Blame"
    public let description = "Shows per-line commit, author, and content for a tracked file using git blame."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Shows per-line commit, author, and content for a tracked file using git blame.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the file to blame."),
                "lineStart": JSONSchema(type: "string", description: "First line number to include (1-based). Default: first line."),
                "lineEnd": JSONSchema(type: "string", description: "Last line number to include (1-based). Default: last line.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawPath = (input["path"] as? String), !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let fileURL = resolveWorkspacePath(rawPath, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(rawPath)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .failure("Blame requires an existing file: \(rawPath)")
        }

        var lineStart: Int?
        var lineEnd: Int?
        if input["lineStart"] != nil {
            guard let parsed = intValue(input["lineStart"]), parsed > 0 else {
                return .failure("Invalid lineStart. Expected a positive integer.")
            }
            lineStart = parsed
        }
        if input["lineEnd"] != nil {
            guard let parsed = intValue(input["lineEnd"]), parsed > 0 else {
                return .failure("Invalid lineEnd. Expected a positive integer.")
            }
            lineEnd = parsed
        }
        if let start = lineStart, let end = lineEnd, end < start {
            return .failure("lineEnd (\(end)) must be greater than or equal to lineStart (\(start)).")
        }

        let relative = relativePath(fileURL, workspaceRoot: context.workspaceRoot)
        let result = runGit(args: ["blame", "--line-porcelain", "--", relative], cwd: context.workspaceRoot)
        guard result.status == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure("Git blame failed for \(relative): \(detail.isEmpty ? "unknown error" : detail)")
        }

        let entries = parsePorcelain(result.output)
        let filtered = entries.filter { entry in
            if let start = lineStart, entry.finalLine < start { return false }
            if let end = lineEnd, entry.finalLine > end { return false }
            return true
        }
        if filtered.isEmpty {
            return .success("No blamed lines in the requested range for \(relative).", data: ["path": relative, "lineCount": "0", "totalLines": "\(entries.count)"])
        }

        let displayLimit = 2000
        let shown = Array(filtered.prefix(displayLimit))
        var lines: [String] = []
        for entry in shown {
            let shortSHA = String(entry.commit.prefix(8))
            let date = formattedDate(from: entry.authorTime)
            lines.append("L\(entry.finalLine) \(shortSHA) \(entry.author) (\(date)) | \(entry.content)")
        }
        var output = lines.joined(separator: "\n")
        if filtered.count > displayLimit {
            output += "\n... truncated to first \(displayLimit) of \(filtered.count) lines."
        }
        return .success("Git blame for \(relative): \(filtered.count) line(s).\n\(output)", data: ["path": relative, "lineCount": "\(filtered.count)", "totalLines": "\(entries.count)", "blame": output])
    }

    private struct BlameEntry {
        let finalLine: Int
        let commit: String
        let author: String
        let authorTime: String
        let summary: String
        let content: String
    }

    private func parsePorcelain(_ output: String) -> [BlameEntry] {
        var entries: [BlameEntry] = []
        var currentCommit = ""
        var currentFinalLine = 0
        var currentAuthor = ""
        var currentTime = ""
        var currentSummary = ""
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            if line.hasPrefix("\t") {
                if !currentCommit.isEmpty {
                    entries.append(BlameEntry(
                        finalLine: currentFinalLine,
                        commit: currentCommit,
                        author: currentAuthor,
                        authorTime: currentTime,
                        summary: currentSummary,
                        content: String(line.dropFirst())
                    ))
                }
                currentCommit = ""
                currentFinalLine = 0
                currentAuthor = ""
                currentTime = ""
                currentSummary = ""
                continue
            }
            if line.hasPrefix("author ") {
                currentAuthor = String(line.dropFirst("author ".count))
                continue
            }
            if line.hasPrefix("author-time ") {
                currentTime = String(line.dropFirst("author-time ".count))
                continue
            }
            if line.hasPrefix("summary ") {
                currentSummary = String(line.dropFirst("summary ".count))
                continue
            }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 4, parts[0].count == 40, isHex(String(parts[0])) {
                currentCommit = String(parts[0])
                currentFinalLine = Int(parts[2]) ?? 0
            }
        }
        return entries
    }

    private func isHex(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy { $0.isHexDigit }
    }

    private func formattedDate(from authorTime: String) -> String {
        guard let interval = Double(authorTime.trimmingCharacters(in: .whitespaces)) else { return authorTime }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: interval))
    }

    private func intValue(_ value: Any?) -> Int? {
        if let s = value as? String {
            return Int(s.trimmingCharacters(in: .whitespaces))
        }
        if let i = value as? Int {
            return i
        }
        if let d = value as? Double, d == d.rounded(), d >= 0, d <= Double(Int.max) {
            return Int(d)
        }
        return nil
    }

    private func resolveWorkspacePath(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
            return nil
        }
        let rootPath = workspaceRoot.standardized.path
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardized
        } else {
            candidate = workspaceRoot.appendingPathComponent(trimmed).standardized
        }
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    private func relativePath(_ url: URL, workspaceRoot: URL) -> String {
        let rootPath = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    private func runGit(args: [String], cwd: URL) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (1, "Failed to launch git: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}
