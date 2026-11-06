// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/AssistGitManager.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/AssistGitManager.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - standalone add(path:) operation
//   - add()'s exclusion of app_summary.md / *.artifact.md files (commit stages everything via add -A)
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AssistContextBuilder — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistContextBuilder.swift`)
//   - GitService — other agent (collab-sourcecontrol) (`SwiftCode/Backend/Git/GitService.swift`)
//   - Project — UNOWNED (no worklist) (`SwiftCode/Models/Project.swift`)
// WIRING / REGISTRATION: None (library type) — consumed by Assist session/agent code and, for tool-adjacent types, by SwiftCodeMCP.

import Foundation

public final class AssistGitManager: Sendable, AssistGitManagerProtocol {
    private let workspaceURL: URL

    public init(project: Project?, workspaceRoot: URL? = nil) {
        if let workspaceRoot = workspaceRoot {
            self.workspaceURL = workspaceRoot
        } else if let proj = project {
            self.workspaceURL = MainActor.assumeIsolated { proj.directoryURL }
        } else {
            self.workspaceURL = MainActor.assumeIsolated { AssistContextBuilder.resolvedWorkspaceRoot() }
        }
    }

    public func status() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--short", "--branch"]
        process.currentDirectoryURL = workspaceURL

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result.isEmpty ? "Clean working tree" : result
    }

    public func commit(message: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["commit", "-am", message]
        process.currentDirectoryURL = workspaceURL

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: data, encoding: .utf8) ?? "Git commit failed"
            throw NSError(domain: "AssistGitManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err])
        }
    }

    public func push() async throws {
        try await GitService.shared.push(repositoryURL: workspaceURL)
    }

    public func diff() async throws -> String {
        let hunks = try await GitService.shared.getDiff(repositoryURL: workspaceURL)
        if hunks.isEmpty {
            return "No git changes detected."
        }
        return hunks.map { hunk in
            "\(hunk.header)\n\(hunk.lines.joined(separator: "\n"))"
        }.joined(separator: "\n\n")
    }

    public func add(path: String) throws {
        // Exclude internal user-facing artifact files from Git staging
        if path.contains("app_summary.md") || path.hasSuffix(".artifact.md") {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["add", path]
        process.currentDirectoryURL = workspaceURL

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
    }
}
