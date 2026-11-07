import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import SwiftCodeAssistant
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
    nonisolated static let failingToolsSensitiveEnvSubstrings = [
        "KEY", "TOKEN", "SECRET", "PASSWORD", "AUTH", "CREDENTIAL",
        "PRIVATE", "BEARER", "SESSION", "COOKIE",
    ]

    nonisolated static func failingToolsIsSensitiveEnvName(_ name: String) -> Bool {
        let upper = name.uppercased()
        return failingToolsSensitiveEnvSubstrings.contains { upper.contains($0) }
    }

    nonisolated static func failingToolsEnvironmentBlock() -> (text: String, count: Int) {
        let env = ProcessInfo.processInfo.environment
        var lines: [String] = []
        for name in env.keys.sorted() {
            if failingToolsIsSensitiveEnvName(name) {
                lines.append("\(name)=<redacted>")
            } else {
                lines.append("\(name)=\(env[name] ?? "")")
            }
        }
        let joined = lines.joined(separator: "\n")
        let (capped, _) = terminalCappedOutput(joined)
        return (capped, env.count)
    }

    struct FailingToolsSnapshotEntry: Sendable {
        var id: String
        var timestamp: Date
        var message: String
    }

    nonisolated static func failingToolsSnapshotHistory() -> [FailingToolsSnapshotEntry] {
        guard let dir = try? projectModelSnapshotsDirectory() else { return [] }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        struct Meta: Decodable { var id: String; var timestamp: Date; var message: String }
        var out: [FailingToolsSnapshotEntry] = []
        for url in items {
            let metaURL = url.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? JSONDecoder().decode(Meta.self, from: data) else { continue }
            out.append(FailingToolsSnapshotEntry(id: meta.id, timestamp: meta.timestamp, message: meta.message))
        }
        out.sort { $0.timestamp > $1.timestamp }
        return Array(out.prefix(10))
    }

    nonisolated static func failingToolsSnapshotLine(_ entry: FailingToolsSnapshotEntry) -> String {
        "\(entry.timestamp): \(entry.message) [\(entry.id)]"
    }

    func failingToolsHostRuns(pid: Int32) -> [(id: String, executable: String, state: String, output: [String])] {
        runs.values.compactMap { run in
            guard run.process.processIdentifier == pid else { return nil }
            let state = run.status.map { "exited with status \($0)" } ?? "running (pid \(pid))"
            return (run.id, run.executable, state, run.output(tail: 100))
        }
    }

    nonisolated static func failingToolsUnifiedLogArgs(pid: Int32) -> [String] {
        ["show", "--style", "compact", "--last", "15m", "--predicate", "processID == \(pid)"]
    }

    nonisolated static func failingToolsJournalArgs(pid: Int32) -> [String] {
        ["--no-pager", "-o", "short", "--since", "15 minutes ago", "_PID=\(pid)"]
    }

    nonisolated static func failingToolsJournalctlPath() -> String? {
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/journalctl") { return "/usr/bin/journalctl" }
        if FileManager.default.isExecutableFile(atPath: "/bin/journalctl") { return "/bin/journalctl" }
        return nil
    }

    nonisolated static func failingToolsProcFacts(pid: Int32) -> String? {
        let dir = "/proc/\(pid)"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
        var parts: [String] = ["Process \(pid):"]
        if let cmdline = try? Data(contentsOf: URL(fileURLWithPath: dir + "/cmdline")) {
            let text = String(decoding: cmdline, as: UTF8.self)
                .split(separator: "\0").joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { parts.append("cmdline: \(text)") }
        }
        if let status = try? String(contentsOfFile: dir + "/status", encoding: .utf8) {
            for line in status.components(separatedBy: .newlines) {
                if line.hasPrefix("State:") || line.hasPrefix("PPid:") || line.hasPrefix("VmRSS:") {
                    parts.append(line.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return parts.joined(separator: "\n")
    }

    func failingToolsProcessExists(pid: Int32) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: "/bin/ps") else { return false }
        guard let run = await archiveRunFixed("/bin/ps", ["-o", "pid=", "-p", "\(pid)"]) else { return false }
        return run.exitCode == 0 && !run.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension SwiftCodeMCPHost {
    func captureLogsReal(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let snapshots = Self.failingToolsSnapshotHistory()
        var logLines = snapshots.map(Self.failingToolsSnapshotLine)
        let memoryKey = call.string("memoryKey") ?? ""
        var memoryIncluded = false
        if !memoryKey.isEmpty,
           let preview = SwiftCodeMemoryGraphStore.shared.retrieve(workspace: memoryWorkspaceKey(in: s), key: memoryKey),
           !preview.isEmpty {
            logLines.append("Memory: \(preview.prefix(500))")
            memoryIncluded = true
        }
        let logs = logLines.isEmpty ? "No logs found in snapshot history." : logLines.joined(separator: "\n")

        let (envText, envCount) = Self.failingToolsEnvironmentBlock()
        let info = ProcessInfo.processInfo
        let header = """
        Environment: \(info.operatingSystemVersionString) (\(envCount) variables; secret-looking values redacted)
        Workspace: \(Self.folder(of: s.model).path)
        """

        var recent: [String] = []
        if let last = runOrder.last, let run = runs[last] {
            recent += ["Latest run \(last) (\(run.executable)):"] + run.output(tail: 50)
        }
        let simLines = simulatorLines(tail: 50)
        if !simLines.isEmpty { recent += ["Simulator output:"] + simLines }
        let recentOutput = recent.joined(separator: "\n")

        var summaryParts = [logs, "", header, envText]
        if !recentOutput.isEmpty { summaryParts += ["", "Recent output:", recentOutput] }
        let summary = summaryParts.joined(separator: "\n")
        return .structured(["logs": .string(logs), "snapshotCount": .int(snapshots.count),
                            "memoryIncluded": .bool(memoryIncluded),
                            "environmentVariableCount": .int(envCount),
                            "environment": .string(envText),
                            "recentOutput": .string(recentOutput)],
                           summary: summary)
    }
}
