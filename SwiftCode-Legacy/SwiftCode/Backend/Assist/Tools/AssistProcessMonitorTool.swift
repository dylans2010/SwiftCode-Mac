//
//  AssistProcessMonitorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistProcessMonitorTool: AssistTool {
    public let id = "process_monitor_tool"
    public let name = "Process Monitor"
    public let description = "Monitors active build, compiler, simulator, and child processes on macOS."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists active developer tool processes (xcodebuild, swift, clang, simctl, lldb) and resource metrics.",
            properties: [
                "filter": JSONSchema(type: "string", description: "Optional process name filter (e.g. 'xcodebuild', 'swift', 'Simulator').")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let filter = input["filter"] as? String

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-eo", "pid,%cpu,%mem,comm"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)

            let lines = output.components(separatedBy: .newlines)
            let devKeywords = ["xcode", "swift", "clang", "simctl", "lldb", "git", "xcrun", "Simulator"]

            var matching: [String] = []
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("PID") { continue }

                if let f = filter, !f.isEmpty {
                    if trimmed.localizedCaseInsensitiveContains(f) {
                        matching.append(trimmed)
                    }
                } else {
                    for kw in devKeywords {
                        if trimmed.localizedCaseInsensitiveContains(kw) {
                            matching.append(trimmed)
                            break
                        }
                    }
                }
            }

            if matching.isEmpty {
                return .success("No active processes matching developer tools or filter '\(filter ?? "Xcode/Swift")'.")
            }

            var report = "### Active Developer Processes (\(matching.count) running):\n\n"
            report += "| PID | %CPU | %MEM | Command |\n|---|---|---|---|\n"
            for m in matching.prefix(25) {
                let parts = m.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 4 {
                    let pid = parts[0]
                    let cpu = parts[1]
                    let mem = parts[2]
                    let cmd = parts.dropFirst(3).joined(separator: " ")
                    let shortCmd = (cmd as NSString).lastPathComponent
                    report += "| `\(pid)` | \(cpu)% | \(mem)% | `\(shortCmd)` |\n"
                }
            }
            return .success(report)
        } catch {
            return .failure("Failed to query processes: \(error.localizedDescription)")
        }
    }
}
