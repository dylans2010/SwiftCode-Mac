import Foundation

public struct AssistGitBisectTool: AssistTool {
    public let id = "git_bisect"
    public let name = "Git Bisect"
    public let description = "Runs one step of git bisect (start, good, bad, skip, reset, or log) in the workspace repository."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs one step of git bisect (start, good, bad, skip, reset, or log) in the workspace repository.",
            properties: [
                "action": JSONSchema(type: "string", description: "Bisect action: start, good, bad, skip, reset, or log. Default: log."),
                "ref": JSONSchema(type: "string", description: "Commit ref for the good or bad action.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let action = ((input["action"] as? String) ?? "log").lowercased()
        let allowed = ["start", "good", "bad", "skip", "reset", "log"]
        guard allowed.contains(action) else {
            return .failure("Invalid bisect action '\(action)'. Allowed: start, good, bad, skip, reset, log.")
        }

        var args = ["bisect", action]
        if action == "good" || action == "bad" {
            if let refRaw = input["ref"] as? String {
                let ref = refRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !ref.isEmpty {
                    guard isValidRef(ref) else {
                        return .failure("Invalid git ref: \(ref)")
                    }
                    args.append(ref)
                }
            }
        }

        let result = runGit(args: args, cwd: context.workspaceRoot)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0 else {
            return .failure("Git bisect \(action) failed: \(output.isEmpty ? "unknown error" : output)")
        }
        let display = output.isEmpty ? "Git bisect \(action) completed with no output." : output
        return .success("Git bisect \(action) succeeded.\n\(display)", data: ["action": action, "output": output])
    }

    private func isValidRef(_ ref: String) -> Bool {
        guard !ref.isEmpty else { return false }
        if ref == "@" { return false }
        if ref.hasPrefix("-") { return false }
        if ref.contains("@{") { return false }
        if ref == "HEAD" { return true }
        if ref.hasPrefix("HEAD~") || ref.hasPrefix("HEAD^") {
            let tail = String(ref.dropFirst(4))
            var index = tail.startIndex
            while index < tail.endIndex {
                let marker = tail[index]
                guard marker == "~" || marker == "^" else { return false }
                index = tail.index(after: index)
                var digitCount = 0
                while index < tail.endIndex, tail[index].isNumber {
                    digitCount += 1
                    index = tail.index(after: index)
                }
                guard digitCount > 0 else { return false }
            }
            return true
        }
        let forbidden = [" ", ";", "&", "|", "`", "$", "(", ")", "<", ">", "\"", "'", "\\", "\n", "\r", "\t", "..", "~", "^", ":", "?", "*", "["]
        for item in forbidden {
            if ref.contains(item) { return false }
        }
        if ref.contains("\0") { return false }
        if ref.hasPrefix("/") || ref.hasSuffix("/") || ref.contains("//") { return false }
        return true
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
