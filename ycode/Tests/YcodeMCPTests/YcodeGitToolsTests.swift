import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

/// The ported Legacy Git / source-control tools (Wave 3, Git slice),
/// each driven black-box through the server's real write-policy path
/// against a throwaway git repository built in a temporary folder.
///
/// Behaviour source: Legacy `AssistConflictMarkerScanTool`,
/// `AssistGitBisectTool`, `AssistGitBlameTool`,
/// `AssistGitBranchCompareTool`, `AssistGitBranchManagerTool`,
/// `AssistGitCherryPickTool`, `AssistGitConflictResolverTool`,
/// `AssistGitLogViewerTool`, `AssistGitPRSummaryTool`,
/// `AssistGitStashTool`, `AssistGitHubRepoTool`,
/// `AssistRecentChangesTool` and `AssistVersionControlOperator`
/// (Dylan's own code, ported under MIT).
///
/// Assertions are on the tool RESULT (message + on-disk / git state),
/// never on internals. Messages quoted verbatim are Legacy's; where
/// the Ycode port may legitimately word a failure differently
/// (path-safety wording), the test asserts the behaviour plus a
/// tolerant message match.
///
/// `github_repo` is the deliberate exception: Legacy implements it
/// as a GitHub API client (network + credential), which Ycode's MCP
/// host does not have, so the test asserts it fails cleanly and
/// fetches nothing.
///
/// The test repositories carry a LOCAL git identity (user.name /
/// user.email / no signing in `.git/config`), so the tools' own git
/// runs can commit and cherry-pick without depending on — or
/// waiting because of — the machine's global git configuration.
@MainActor
@Suite(.serialized) struct YcodeGitToolsTests {
    /// The 13 Wave 3 Git tool IDs, verified live from the Legacy
    /// registry (`AssistToolRegistry.registerAllTools` + each
    /// tool's `id`).
    static let gitIDs = ["conflict_marker_scan", "git_bisect", "git_blame_inspector", "git_branch_compare",
                         "git_branch_manager", "git_cherry_pick", "git_conflict_resolver", "git_log_viewer",
                         "git_pr_summary", "git_stash_operator", "github_repo", "recent_changes",
                         "version_control_operator"]

    /// Runs git in `dir` (identity via `-c`, global config ignored)
    /// and returns stdout; throws with stderr when git exits non-zero.
    static func git(_ dir: URL, _ args: String...) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path, "-c", "user.name=Ada", "-c", "user.email=ada@ycode.invalid",
                       "-c", "commit.gpgsign=false"] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_TERMINAL_PROMPT"] = "0"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        // stderr on its own thread: reading the two pipes one after the
        // other deadlocks when the child fills the second one first.
        final class Box: @unchecked Sendable { var data = Data() }
        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        Thread { errBox.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }.start()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "TestGit", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: String(decoding: errBox.data, as: UTF8.self)])
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// A Swift package in a git repository: `main` with one commit
    /// ("Initial commit"), plus a `feature` branch. The repository's
    /// local config carries the test identity, so the tools under
    /// test can commit and cherry-pick in it.
    func makeRepo(_ name: String, diverged: Bool = false) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ycode-git-\(name)-\(UUID().uuidString)")
        let sources = dir.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.executableTarget(name: \"App\")])\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "let a = 1\nprint(a)\n".write(to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        _ = try Self.git(dir, "init", "-q", "-b", "main")
        _ = try Self.git(dir, "config", "user.name", "Ada")
        _ = try Self.git(dir, "config", "user.email", "ada@ycode.invalid")
        _ = try Self.git(dir, "config", "commit.gpgsign", "false")
        _ = try Self.git(dir, "add", "-A")
        _ = try Self.git(dir, "commit", "-qm", "Initial commit")
        _ = try Self.git(dir, "branch", "feature")
        if diverged {
            try "let a = 2\nprint(a)\n".write(to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
            _ = try Self.git(dir, "commit", "-qam", "Second on main")
            _ = try Self.git(dir, "checkout", "-q", "feature")
            try "let b = 1\n".write(to: sources.appendingPathComponent("New.swift"), atomically: true, encoding: .utf8)
            _ = try Self.git(dir, "add", "-A")
            _ = try Self.git(dir, "commit", "-qm", "Feature work")
            _ = try Self.git(dir, "checkout", "-q", "main")
        }
        return dir
    }

    /// A Swift package folder with NO git repository.
    func makePlainFolder(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ycode-git-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources/App"), withIntermediateDirectories: true)
        try "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.executableTarget(name: \"App\")])\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    /// Opens `dir` and installs the ported Git tools on the server
    /// (same shape as Wave 2's `opened`, which installs
    /// `fileWritingTools` the same way — `installTools()` does not
    /// wire `gitTools` yet; the coordinator owns that).
    func opened(_ dir: URL, policy: MCPWritePolicy = .readOnly) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.gitTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.gitTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(dir.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    final class Reviews: @unchecked Sendable {
        var changes: [MCPChange] = []
        var accept = false
    }

    func writeFile(_ dir: URL, _ rel: String, _ content: String) throws {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func readFile(_ dir: URL, _ rel: String) -> String {
        (try? String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)) ?? ""
    }

    func exists(_ dir: URL, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(rel).path)
    }

    // MARK: - Registration

    @Test func gitToolsListTheThirteenTools() async throws {
        let host = YcodeMCPHost()
        let tools = host.gitTools
        #expect(Set(tools.map(\.name)) == Set(Self.gitIDs), "gitTools must be exactly the 13 Legacy Git tools")
        #expect(tools.count == 13, "no duplicate registrations")
        for tool in tools {
            switch tool.name {
            case "conflict_marker_scan", "git_blame_inspector", "git_branch_compare", "git_log_viewer",
                 "git_pr_summary", "github_repo", "recent_changes":
                #expect(tool.annotations.readOnly && !tool.writes, "\(tool.name) must be read-only")
            case "version_control_operator":
                #expect(!tool.annotations.readOnly && tool.annotations.destructive && tool.writes,
                        "version_control_operator is potentiallyDestructive")
            case "git_bisect":
                #expect(!tool.annotations.readOnly && !tool.annotations.idempotent && tool.writes,
                        "git_bisect is Legacy risk .execution: mutating, not idempotent")
            default:
                #expect(!tool.annotations.readOnly && tool.annotations.idempotent && tool.writes,
                        "\(tool.name) must be a safeMutation write tool")
            }
        }
    }

    // MARK: - Read-only git tools

    @Test func logViewerListsCommits() async throws {
        let dir = try makeRepo("log", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let all = try await host.server.callTool("git_log_viewer", [:])
        #expect(!all.isToolError, "\(all.resultText)")
        #expect(all.resultText.contains("Initial commit") && all.resultText.contains("Second on main"))
        let one = try await host.server.callTool("git_log_viewer", ["maxCount": .int(1)])
        #expect(one.resultText.contains("Second on main") && !one.resultText.contains("Initial commit"))
        #expect(one.resultText.contains("(1 entries)"))
        let filtered = try await host.server.callTool("git_log_viewer", ["path": .string("Sources/App/New.swift")])
        #expect(!filtered.isToolError, "\(filtered.resultText)")
        #expect(filtered.resultText.contains("No commits found"))
    }

    @Test func logViewerFailsHonestlyOutsideARepository() async throws {
        let dir = try makePlainFolder("plain")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await host.server.callTool("git_log_viewer", [:])
        #expect(r.isToolError && r.resultText.contains("not a git repository"), "\(r.resultText)")
    }

    @Test func branchCompareCountsDivergentCommits() async throws {
        let dir = try makeRepo("compare", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await host.server.callTool("git_branch_compare", ["base": .string("main"), "head": .string("feature")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("Feature work") && r.resultText.contains("Commits in feature not in main (1)"))
        #expect(r.structured?["commitCount"]?.int == 1)
        let bad = try await host.server.callTool("git_branch_compare", ["base": .string("main; rm -rf /"), "head": .string("feature")])
        #expect(bad.isToolError && bad.resultText.contains("Invalid git ref for base"))
    }

    @Test func blameInspectorShowsBlamedLines() async throws {
        let dir = try makeRepo("blame", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await host.server.callTool("git_blame_inspector", ["path": .string("Sources/App/main.swift")])
        #expect(!r.isToolError, "\(r.resultText)")
        // Legacy's output is the `git blame -s` rendering: short hash,
        // line number, line text (no author — `-s` suppresses it).
        #expect(r.resultText.contains("Git blame for `Sources/App/main.swift`") && r.resultText.contains("let a = 2"))
        let ranged = try await host.server.callTool("git_blame_inspector", ["path": .string("Sources/App/main.swift"),
                                                                             "startLine": .int(1), "endLine": .int(1)])
        #expect(!ranged.isToolError, "\(ranged.resultText)")
        #expect(ranged.resultText.contains("let a = 2") && !ranged.resultText.contains("print(a)"))
    }

    @Test func conflictMarkerScanFindsMarkers() async throws {
        let dir = try makeRepo("markers")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let clean = try await host.server.callTool("conflict_marker_scan", [:])
        #expect(!clean.isToolError, "\(clean.resultText)")
        #expect(clean.resultText.contains("No merge-conflict markers found"))
        #expect(clean.structured?["fileCount"]?.int == 0)
        try writeFile(dir, "Sources/App/Conflicted.swift", "let a = 1\n<<<<<<< HEAD\nlet b = 1\n=======\nlet b = 2\n>>>>>>> feature\nprint(a)\n")
        let found = try await host.server.callTool("conflict_marker_scan", [:])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.resultText.contains("Sources/App/Conflicted.swift") && found.resultText.contains("lines 2, 4, 6"))
        #expect(found.structured?["fileCount"]?.int == 1)
    }

    @Test func recentChangesListsTouchedFiles() async throws {
        let dir = try makeRepo("recent")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        try writeFile(dir, "Sources/App/Fresh.swift", "let fresh = true\n")
        let r = try await host.server.callTool("recent_changes", ["hours": .int(1)])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("Sources/App/Fresh.swift"))
        #expect((r.structured?["count"]?.int ?? 0) >= 1)
    }

    @Test func prSummaryIsLocalMarkdown() async throws {
        let dir = try makeRepo("pr", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await host.server.callTool("git_pr_summary", ["base": .string("main"), "head": .string("feature")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("# PR Summary") && r.resultText.contains("Feature work"))
        #expect(r.resultText.contains("Files changed: 1 | Insertions: 1 | Deletions: 0"))
        #expect(r.structured?["commitCount"]?.int == 1 && r.structured?["fileCount"]?.int == 1)
        #expect(r.structured?["insertions"]?.int == 1 && r.structured?["deletions"]?.int == 0)
    }

    // MARK: - Writing git tools and the approval gate

    @Test func branchManagerListsCreatesAndRefusesInReadOnlyMode() async throws {
        let dir = try makeRepo("branches", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let list = try await host.server.callTool("git_branch_manager", ["action": .string("list")])
        #expect(!list.isToolError, "\(list.resultText)")
        #expect(list.resultText.contains("main") && list.resultText.contains("feature"))
        let created = try await host.server.callTool("git_branch_manager", ["action": .string("create"), "branchName": .string("topic/x")])
        #expect(!created.isToolError, "\(created.resultText)")
        let current = try await host.server.callTool("git_branch_manager", ["action": .string("current")])
        #expect(current.resultText.contains("topic/x"))
        let badName = try await host.server.callTool("git_branch_manager", ["action": .string("create"), "branchName": .string("--help")])
        #expect(badName.isToolError && badName.resultText.contains("Invalid branch name"))
        // Read-only mode refuses even the read actions of this
        // writes:true tool (the Wave 2 dry-run precedent).
        let readOnlyHost = try await opened(dir)
        let refused = try await readOnlyHost.server.callTool("git_branch_manager", ["action": .string("list")])
        #expect(refused.isToolError && refused.resultText.contains("read-only"), "\(refused.resultText)")
    }

    @Test func reviewRejectsBranchDelete() async throws {
        let dir = try makeRepo("review-delete")
        defer { try? FileManager.default.removeItem(at: dir) }
        let allowHost = try await opened(dir, policy: .allow)
        let created = try await allowHost.server.callTool("git_branch_manager", ["action": .string("create"), "branchName": .string("doomed")])
        #expect(!created.isToolError, "\(created.resultText)")
        let switched = try await allowHost.server.callTool("git_branch_manager", ["action": .string("switch"), "branchName": .string("main")])
        #expect(!switched.isToolError, "\(switched.resultText)")
        let reviews = Reviews()
        let reviewHost = try await opened(dir, policy: .review { c in reviews.changes.append(c); return reviews.accept })
        let rejected = try await reviewHost.server.callTool("git_branch_manager", ["action": .string("delete"), "branchName": .string("doomed")])
        #expect(rejected.isToolError && rejected.resultText == MCPServer.rejectedMessage)
        #expect(reviews.changes.first?.tool == "git_branch_manager")
        let list = try await allowHost.server.callTool("git_branch_manager", ["action": .string("list")])
        #expect(list.resultText.contains("doomed"), "rejected delete must leave the branch in place")
        reviews.accept = true
        let deleted = try await reviewHost.server.callTool("git_branch_manager", ["action": .string("delete"), "branchName": .string("doomed")])
        #expect(!deleted.isToolError, "\(deleted.resultText)")
    }

    @Test func stashSavePopRoundTrip() async throws {
        let dir = try makeRepo("stash")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        try writeFile(dir, "Sources/App/main.swift", "let a = 9\nprint(a)\n")
        let saved = try await host.server.callTool("git_stash_operator", ["action": .string("save"), "message": .string("wip")])
        #expect(!saved.isToolError, "\(saved.resultText)")
        #expect(readFile(dir, "Sources/App/main.swift").contains("let a = 1"), "save must restore the committed file")
        let list = try await host.server.callTool("git_stash_operator", ["action": .string("list")])
        #expect(list.resultText.contains("wip"))
        let popped = try await host.server.callTool("git_stash_operator", ["action": .string("pop")])
        #expect(!popped.isToolError, "\(popped.resultText)")
        #expect(readFile(dir, "Sources/App/main.swift").contains("let a = 9"), "pop must restore the stashed change")
        let bad = try await host.server.callTool("git_stash_operator", ["action": .string("drop"), "stashIndex": .string("nonsense")])
        #expect(bad.isToolError && bad.resultText.contains("Invalid stash identifier"))
    }

    @Test func cherryPickAppliesFeatureCommit() async throws {
        let dir = try makeRepo("pick", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let sha = try Self.git(dir, "rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines)
        let picked = try await host.server.callTool("git_cherry_pick", ["commit": .string(sha)])
        #expect(!picked.isToolError, "\(picked.resultText)")
        #expect(picked.resultText.contains("Cherry-picked \(sha)"))
        #expect(exists(dir, "Sources/App/New.swift") && readFile(dir, "Sources/App/New.swift").contains("let b = 1"))
        let invalid = try await host.server.callTool("git_cherry_pick", ["commit": .string("not-a-ref!!!")])
        #expect(invalid.isToolError && invalid.resultText.contains("Invalid commit"))
    }

    @Test func conflictResolverInspectsAndTakesOurs() async throws {
        let dir = try makeRepo("resolve")
        defer { try? FileManager.default.removeItem(at: dir) }
        // `inspect` is a read, but the tool is writes:true, so a
        // read-only server refuses it (same rule as branch list).
        let readOnlyHost = try await opened(dir)
        try writeFile(dir, "Sources/App/Conflicted.swift", "let a = 1\n<<<<<<< HEAD\nlet b = 1\n=======\nlet b = 2\n>>>>>>> feature\nprint(a)\n")
        let refused = try await readOnlyHost.server.callTool("git_conflict_resolver",
                                                             ["path": .string("Sources/App/Conflicted.swift"),
                                                              "resolution": .string("inspect")])
        #expect(refused.isToolError && refused.resultText.contains("read-only"), "\(refused.resultText)")
        let host = try await opened(dir, policy: .allow)
        let report = try await host.server.callTool("git_conflict_resolver",
                                                    ["path": .string("Sources/App/Conflicted.swift"),
                                                     "resolution": .string("inspect")])
        #expect(!report.isToolError, "\(report.resultText)")
        #expect(report.resultText.contains("Detected 1 Merge Conflict") && report.resultText.contains("<<<<<<< HEAD"))
        // An unknown resolution fails while markers are still present
        // (Legacy validates the markers before the resolution).
        let unknown = try await host.server.callTool("git_conflict_resolver",
                                                     ["path": .string("Sources/App/Conflicted.swift"),
                                                      "resolution": .string("take_both")])
        #expect(unknown.isToolError && unknown.resultText.contains("Unknown resolution"), "\(unknown.resultText)")
        let resolved = try await host.server.callTool("git_conflict_resolver",
                                                      ["path": .string("Sources/App/Conflicted.swift"),
                                                       "resolution": .string("take_ours")])
        #expect(!resolved.isToolError, "\(resolved.resultText)")
        let text = readFile(dir, "Sources/App/Conflicted.swift")
        #expect(text.contains("let b = 1") && !text.contains("let b = 2") && !text.contains("<<<<<<<"))
        // After resolution there is nothing left to resolve.
        let clean = try await host.server.callTool("git_conflict_resolver",
                                                   ["path": .string("Sources/App/Conflicted.swift"),
                                                    "resolution": .string("inspect")])
        #expect(!clean.isToolError && clean.resultText.contains("No active Git conflict markers"), "\(clean.resultText)")
    }

    @Test func bisectStepsAndRejectsBadAction() async throws {
        let dir = try makeRepo("bisect", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let bad = try await host.server.callTool("git_bisect", ["action": .string("jump")])
        #expect(bad.isToolError && bad.resultText.contains("Invalid bisect action"))
        // `log` with no bisect in progress fails with git's own
        // message, exactly as Legacy reports it.
        let noBisect = try await host.server.callTool("git_bisect", ["action": .string("log")])
        #expect(noBisect.isToolError && noBisect.resultText.contains("not bisecting"), "\(noBisect.resultText)")
        let started = try await host.server.callTool("git_bisect", ["action": .string("start")])
        #expect(!started.isToolError, "\(started.resultText)")
        #expect(started.resultText.contains("Git bisect start succeeded"))
        let logged = try await host.server.callTool("git_bisect", ["action": .string("log")])
        #expect(!logged.isToolError, "\(logged.resultText)")
        #expect(logged.resultText.contains("git bisect start"))
        let reset = try await host.server.callTool("git_bisect", ["action": .string("reset")])
        #expect(!reset.isToolError, "\(reset.resultText)")
    }

    @Test func versionControlOperatorStatusCommitAndRemoteRejection() async throws {
        let dir = try makeRepo("vco")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let status = try await host.server.callTool("version_control_operator", ["action": .string("status")])
        #expect(!status.isToolError, "\(status.resultText)")
        #expect(status.resultText.contains("Git action executed: status"))
        let push = try await host.server.callTool("version_control_operator", ["action": .string("push")])
        #expect(push.isToolError && push.resultText.contains("later wave"), "\(push.resultText)")
        let unknown = try await host.server.callTool("version_control_operator", ["action": .string("dance")])
        #expect(unknown.isToolError && unknown.resultText.contains("Unknown git action"))
        try writeFile(dir, "Sources/App/main.swift", "let a = 5\nprint(a)\n")
        let committed = try await host.server.callTool("version_control_operator",
                                                       ["action": .string("commit"), "message": .string("Test commit")])
        #expect(!committed.isToolError, "\(committed.resultText)")
        let log = try await host.server.callTool("git_log_viewer", ["maxCount": .int(1)])
        #expect(log.resultText.contains("Test commit"))
        // A rejected rollback leaves HEAD where it was.
        let reviews = Reviews()
        host.server.writePolicy = .review { c in reviews.changes.append(c); return reviews.accept }
        let rejected = try await host.server.callTool("version_control_operator",
                                                      ["action": .string("rollback"), "ref": .string("HEAD~1")])
        #expect(rejected.isToolError && rejected.resultText == MCPServer.rejectedMessage)
        let stillThere = try await host.server.callTool("git_log_viewer", ["maxCount": .int(1)])
        #expect(stillThere.resultText.contains("Test commit"))
    }

    // MARK: - Honestly-failing tool and confinement

    @Test func gitHubRepoFailsHonestlyWithoutFetching() async throws {
        let dir = try makeRepo("github")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await host.server.callTool("github_repo", ["operation": .string("repository_info"),
                                                               "owner": .string("dylans2010"), "repo": .string("SwiftCode-Mac")])
        #expect(r.isToolError, "github_repo must fail: Ycode has no GitHub client")
        #expect(r.resultText.contains("GitHub") && r.resultText.contains("does not have yet"))
        #expect(!r.resultText.contains("stargazers") && !r.resultText.contains("default_branch"),
                "no GitHub data may be faked: \(r.resultText)")
    }

    @Test func workspaceConfinementRejectsEscapes() async throws {
        let dir = try makeRepo("confine")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let blame = try await host.server.callTool("git_blame_inspector", ["path": .string("../outside.swift")])
        #expect(blame.isToolError && blame.resultText.contains("outside the workspace"), "\(blame.resultText)")
        let log = try await host.server.callTool("git_log_viewer", ["path": .string("../../etc")])
        #expect(log.isToolError && log.resultText.contains("outside the workspace"), "\(log.resultText)")
        let resolve = try await host.server.callTool("git_conflict_resolver", ["path": .string("/etc/passwd")])
        #expect(resolve.isToolError, "an absolute path outside the workspace must be refused: \(resolve.resultText)")
    }
}
