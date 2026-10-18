//
//  AssistGitBlameTool.swift
//  SwiftCode
//

import Foundation

public struct AssistGitBlameTool: AssistTool {
    public let id = "git_blame_inspector"
    public let name = "Git Blame Inspector"
    public let description = "Inspects author, commit hash, date, and commit message for specific lines in a workspace file."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs git blame on a target file to analyze authorship, commit history, and modifications for specific lines.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to the file in workspace."),
                "startLine": JSONSchema(type: "integer", description: "Optional starting line number."),
                "endLine": JSONSchema(type: "integer", description: "Optional ending line number.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        let startLine = input["startLine"] as? Int
        let endLine = input["endLine"] as? Int

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        var args = ["blame", "--porcelain"]
        if let s = startLine, let e = endLine, s > 0, e >= s {
            args.append("-L")
            args.append("\(s),\(e)")
        } else if let s = startLine, s > 0 {
            args.append("-L")
            args.append("\(s),\(s + 30)")
        }
        args.append(path)
        proc.arguments = args
        proc.currentDirectoryURL = context.workspaceRoot

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(decoding: data, as: UTF8.self)

            if proc.terminationStatus != 0 {
                return .failure("git blame failed: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            // Also run normal formatted blame for readable snippet
            let formatProc = Process()
            formatProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            var fArgs = ["blame", "-s"]
            if let s = startLine, let e = endLine, s > 0, e >= s {
                fArgs.append("-L")
                fArgs.append("\(s),\(e)")
            }
            fArgs.append(path)
            formatProc.arguments = fArgs
            formatProc.currentDirectoryURL = context.workspaceRoot

            let fPipe = Pipe()
            formatProc.standardOutput = fPipe
            formatProc.standardError = fPipe
            try? formatProc.run()
            formatProc.waitUntilExit()
            let fData = fPipe.fileHandleForReading.readDataToEndOfFile()
            let readable = String(decoding: fData, as: UTF8.self)

            let lines = readable.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return .success("Git blame for `\(path)`:\n\n" + lines.prefix(50).joined(separator: "\n"))
        } catch {
            return .failure("Failed to execute git blame: \(error.localizedDescription)")
        }
    }
}
