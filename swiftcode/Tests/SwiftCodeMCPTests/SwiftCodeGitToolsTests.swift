import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

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
/// the SwiftCode port may legitimately word a failure differently
/// (path-safety wording), the test asserts the behaviour plus a
/// tolerant message match.
///
/// `github_repo` reads live repositories through the shared
/// `GitHubClient` (Wave 10); its tests run against the URLProtocol
/// stub (`installGitHubStub` in TestSupport), never the live
/// network.
///
/// The test repositories carry a LOCAL git identity (user.name /
/// user.email / no signing in `.git/config`), so the tools' own git
/// runs can commit and cherry-pick without depending on — or
/// waiting because of — the machine's global git configuration.
@MainActor
@Suite(.serialized) struct SwiftCodeGitToolsTests {
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
        p.arguments = ["-C", dir.path, "-c", "user.name=Ada", "-c", "user.email=ada@swiftcode.invalid",
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
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-git-\(name)-\(UUID().uuidString)")
        let sources = dir.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.executableTarget(name: \"App\")])\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "let a = 1\nprint(a)\n".write(to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        _ = try Self.git(dir, "init", "-q", "-b", "main")
        _ = try Self.git(dir, "config", "user.name", "Ada")
        _ = try Self.git(dir, "config", "user.email", "ada@swiftcode.invalid")
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
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-git-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources/App"), withIntermediateDirectories: true)
        try "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.executableTarget(name: \"App\")])\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    /// A bare repository inside `workspace`, used as the "remote"
    /// for push/pull/fetch/clone: a local path inside the workspace
    /// is an allowed remote under the Wave 10 URL policy, so no
    /// network is involved.
    func makeBareRemote(in workspace: URL, name: String = "remote.git") throws -> URL {
        _ = try Self.git(workspace, "init", "--bare", "-q", name)
        return workspace.appendingPathComponent(name)
    }

    /// A second working copy cloned from `remote` into a fresh
    /// temporary folder (test scaffolding only — the tools under
    /// test never see a path outside the workspace).
    func makeSecondCopy(_ name: String, from remote: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-git-\(name)-\(UUID().uuidString)")
        _ = try Self.git(FileManager.default.temporaryDirectory, "clone", "-q", remote.path, dest.path)
        return dest
    }

    /// Opens `dir` and installs the ported Git tools on the server
    /// (same shape as Wave 2's `opened`, which installs
    /// `fileWritingTools` the same way — `installTools()` does not
    /// wire `gitTools` yet; the coordinator owns that).
    func opened(_ dir: URL, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
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
        let host = SwiftCodeMCPHost()
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
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
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

    @Test func versionControlOperatorStatusCommitAndRollback() async throws {
        let dir = try makeRepo("vco")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let status = try await host.server.callTool("version_control_operator", ["action": .string("status")])
        #expect(!status.isToolError, "\(status.resultText)")
        #expect(status.resultText.contains("Git action executed: status"))
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
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        let stillThere = try await host.server.callTool("git_log_viewer", ["maxCount": .int(1)])
        #expect(stillThere.resultText.contains("Test commit"))
    }

    @Test func versionControlOperatorRemoteActionsPushPullFetchClone() async throws {
        // Wave 10 addition (Legacy implements no remote
        // sub-operations at all): push/pull/fetch/clone against a
        // bare remote inside the workspace, over a local path.
        let dir = try makeRepo("vco-remote")
        defer { try? FileManager.default.removeItem(at: dir) }
        let remote = try makeBareRemote(in: dir)
        _ = try Self.git(dir, "remote", "add", "origin", remote.path)
        _ = try Self.git(dir, "push", "-q", "-u", "origin", "main")
        let host = try await opened(dir, policy: .allow)
        // Push: a new commit in the workspace lands in the bare remote.
        try writeFile(dir, "Sources/App/Pushed.swift", "let p = 1\n")
        _ = try Self.git(dir, "add", "-A")
        _ = try Self.git(dir, "commit", "-qm", "VCO pushed commit")
        let pushed = try await host.server.callTool("version_control_operator", ["action": .string("push")])
        #expect(!pushed.isToolError, "\(pushed.resultText)")
        #expect(pushed.resultText.contains("Git action executed: push"))
        let remoteLog = try Self.git(remote, "log", "--oneline", "main")
        #expect(remoteLog.contains("VCO pushed commit"), "\(remoteLog)")
        // Fetch with an explicit remote name, then pull a commit
        // made in a second copy.
        let fetched = try await host.server.callTool("version_control_operator",
                                                     ["action": .string("fetch"), "remote": .string("origin")])
        #expect(!fetched.isToolError, "\(fetched.resultText)")
        #expect(fetched.resultText.contains("Git action executed: fetch"))
        let other = try makeSecondCopy("vco-other", from: remote)
        defer { try? FileManager.default.removeItem(at: other) }
        try writeFile(other, "Sources/App/Pulled.swift", "let q = 1\n")
        _ = try Self.git(other, "add", "-A")
        _ = try Self.git(other, "commit", "-qm", "VCO pulled commit")
        _ = try Self.git(other, "push", "-q", "origin", "main")
        let pulled = try await host.server.callTool("version_control_operator", ["action": .string("pull")])
        #expect(!pulled.isToolError, "\(pulled.resultText)")
        #expect(pulled.resultText.contains("Git action executed: pull"))
        #expect(readFile(dir, "Sources/App/Pulled.swift").contains("let q = 1"))
        // Clone the bare remote to a folder inside the workspace.
        let cloned = try await host.server.callTool("version_control_operator",
                                                    ["action": .string("clone"),
                                                     "url": .string(remote.path),
                                                     "destination": .string("vco-clone")])
        #expect(!cloned.isToolError, "\(cloned.resultText)")
        #expect(cloned.resultText.contains("Git action executed: clone"))
        #expect(readFile(dir, "vco-clone/Sources/App/main.swift").contains("let a = 1"))
        // Policy and validation failures stay honest errors.
        let badURL = try await host.server.callTool("version_control_operator",
                                                    ["action": .string("clone"),
                                                     "url": .string("ftp://example.invalid/repo.git"),
                                                     "destination": .string("vco-clone-bad")])
        #expect(badURL.isToolError && badURL.firstText.contains("Unsupported remote URL"), "\(badURL.firstText)")
        #expect(!exists(dir, "vco-clone-bad"))
        let badRemote = try await host.server.callTool("version_control_operator",
                                                       ["action": .string("fetch"), "remote": .string("--help")])
        #expect(badRemote.isToolError && badRemote.firstText.contains("Invalid remote name"), "\(badRemote.firstText)")
        let noURL = try await host.server.callTool("version_control_operator", ["action": .string("clone")])
        #expect(noURL.isToolError && noURL.firstText.contains("requires 'url'"), "\(noURL.firstText)")
    }

    // MARK: - `github_repo` (Wave 10: wired to the real GitHub API)

    /// Fixture JSON for `github_repo` (sibling `SwiftCodeGitHubTests`
    /// shapes, synthetic data, no real token anywhere).
    static let gitHubRepoJSON = """
        {"name":"Hello-World","full_name":"octocat/Hello-World","owner":{"login":"octocat"},"description":"My first repo","private":false,"html_url":"https://github.com/octocat/Hello-World","default_branch":"main","stargazers_count":42,"forks_count":7,"language":"Swift","created_at":"2024-01-15T10:30:00Z","updated_at":"2024-02-01T12:00:00Z","pushed_at":"2024-02-01T12:00:00Z"}
        """
    static let gitHubTreeJSON = """
        {"sha":"mainsha","url":"https://api.github.com/repos/octocat/Hello-World/git/trees/main","tree":[{"path":"README.md","mode":"100644","type":"blob","sha":"aaa","size":14},{"path":"Package.swift","mode":"100644","type":"blob","sha":"bbb","size":91},{"path":"Sources","mode":"040000","type":"tree","sha":"ccc"},{"path":"Sources/main.swift","mode":"100644","type":"blob","sha":"ddd","size":19},{"path":"logo.png","mode":"100644","type":"blob","sha":"eee","size":1024},{"path":"node_modules/dep/index.js","mode":"100644","type":"blob","sha":"fff","size":10}],"truncated":false}
        """
    static let gitHubSearchCodeJSON = """
        {"total_count":1,"incomplete_results":false,"items":[{"name":"main.swift","path":"Sources/main.swift","repository":{"full_name":"octocat/Hello-World"}}]}
        """

    /// One file's Contents API fixture (base64 `content`).
    /// Nonisolated: called from the stub router, which is `@Sendable`.
    nonisolated static func gitHubContentJSON(name: String, path: String, size: Int, base64: String) -> String {
        "{\"name\":\"\(name)\",\"path\":\"\(path)\",\"sha\":\"aaa\",\"size\":\(size),\"content\":\"\(base64)\",\"encoding\":\"base64\"}"
    }

    /// The stub router for the `github_repo` operation tests:
    /// repository metadata, the recursive tree, the three text
    /// files' contents, and code search. Anything else is a 404.
    /// Nonisolated: it is passed as the stub's `@Sendable` handler.
    nonisolated static func gitHubRepoStub(_ request: URLRequest) -> (status: Int, headers: [String: String], body: Data) {
        switch request.url?.path {
        case "/repos/octocat/Hello-World":
            return gitHubStubOK(gitHubRepoJSON)
        case "/repos/octocat/Hello-World/git/trees/main":
            return gitHubStubOK(gitHubTreeJSON)
        case "/repos/octocat/Hello-World/contents/Package.swift":
            return gitHubStubOK(gitHubContentJSON(name: "Package.swift", path: "Package.swift", size: 91,
                                                  base64: "Ly8gc3dpZnQtdG9vbHMtdmVyc2lvbjogNS45CmltcG9ydCBQYWNrYWdlRGVzY3JpcHRpb24KbGV0IHBhY2thZ2UgPSBQYWNrYWdlKG5hbWU6ICJBcHAiKQo="))
        case "/repos/octocat/Hello-World/contents/Sources/main.swift":
            return gitHubStubOK(gitHubContentJSON(name: "main.swift", path: "Sources/main.swift", size: 19,
                                                  base64: "bGV0IGEgPSAxCnByaW50KGEpCg=="))
        case "/repos/octocat/Hello-World/contents/README.md":
            return gitHubStubOK(gitHubContentJSON(name: "README.md", path: "README.md", size: 14,
                                                  base64: "IyBIZWxsby1Xb3JsZAo="))
        case "/search/code":
            return gitHubStubOK(gitHubSearchCodeJSON)
        default:
            return gitHubStubError(404, "Not Found")
        }
    }

    @Test func gitHubRepoRepositoryInfo() async throws {
        let dir = try makeRepo("github-info")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        installGitHubStub(token: nil, handler: Self.gitHubRepoStub)
        let r = try await host.server.callTool("github_repo", ["operation": .string("repository_info"),
                                                               "owner": .string("octocat"), "repo": .string("Hello-World")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Retrieved repository metadata for octocat/Hello-World."))
        #expect(r.resultText.contains("Default branch: main"))
        #expect(r.resultText.contains("Stars: 42"))
        #expect(r.structured?["stars"]?.int == 42)
        #expect(r.structured?["fullName"]?.string == "octocat/Hello-World")
    }

    @Test func gitHubRepoGetTree() async throws {
        let dir = try makeRepo("github-tree")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        installGitHubStub(token: nil, handler: Self.gitHubRepoStub)
        let r = try await host.server.callTool("github_repo", ["operation": .string("get_tree"),
                                                               "owner": .string("octocat"), "repo": .string("Hello-World")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Retrieved file tree for octocat/Hello-World (6 shown)."))
        #expect(r.resultText.contains("Entries: 6"))
        #expect(r.resultText.contains("- Package.swift 91"))
        #expect(r.resultText.contains("d Sources"))
        #expect(r.structured?["count"]?.int == 6)
    }

    @Test func gitHubRepoGetFile() async throws {
        let dir = try makeRepo("github-file")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        installGitHubStub(token: nil, handler: Self.gitHubRepoStub)
        let r = try await host.server.callTool("github_repo", ["operation": .string("get_file"),
                                                               "owner": .string("octocat"), "repo": .string("Hello-World"),
                                                               "path": .string("Package.swift")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Retrieved 'Package.swift' (91 bytes)."))
        #expect(r.resultText.contains("let package = Package(name: \"App\")"))
    }

    @Test func gitHubRepoGetFileReportsBinaryByExtension() async throws {
        let dir = try makeRepo("github-binary")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        installGitHubStub(token: nil, handler: Self.gitHubRepoStub)
        let r = try await host.server.callTool("github_repo", ["operation": .string("get_file"),
                                                               "owner": .string("octocat"), "repo": .string("Hello-World"),
                                                               "path": .string("logo.png")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("is a binary file"))
        #expect(StubGitHubProtocol.requests.isEmpty, "a binary file is classified without fetching it")
    }

    @Test func gitHubRepoGetDirectoryListsOneLevel() async throws {
        let dir = try makeRepo("github-dir")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        installGitHubStub(token: nil, handler: Self.gitHubRepoStub)
        let r = try await host.server.callTool("github_repo", ["operation": .string("get_directory"),
                                                               "owner": .string("octocat"), "repo": .string("Hello-World"),
                                                               "path": .string("Sources")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("- [file] Sources/main.swift (19 bytes)"))
        #expect(!r.resultText.contains("Package.swift"), "one level only: the root files are not listed")
        #expect(r.structured?["count"]?.int == 1)
    }

    @Test func gitHubRepoListFilesRecursive() async throws {
        let dir = try makeRepo("github-list")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        installGitHubStub(token: nil, handler: Self.gitHubRepoStub)
        let r = try await host.server.callTool("github_repo", ["operation": .string("list_files"),
                                                               "owner": .string("octocat"), "repo": .string("Hello-World")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("- [file] Sources/main.swift (19 bytes)"))
        #expect(r.resultText.contains("- [file] logo.png (1024 bytes)"))
        #expect(!r.resultText.contains("d Sources"), "recursive list_files lists blobs only")
        #expect(r.structured?["count"]?.int == 5)
    }

    @Test func gitHubRepoSearchCode() async throws {
        let dir = try makeRepo("github-search")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        installGitHubStub(token: nil, handler: Self.gitHubRepoStub)
        let r = try await host.server.callTool("github_repo", ["operation": .string("search_code"),
                                                               "owner": .string("octocat"), "repo": .string("Hello-World"),
                                                               "query": .string("main")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Found 1 match for \"main\" (1 shown)."))
        #expect(r.resultText.contains("- Sources/main.swift (main.swift)"))
        let request = try #require(StubGitHubProtocol.requests.first)
        #expect(requestQueryItems(of: request)["q"] == "repo:octocat/Hello-World main")
    }

    @Test func gitHubRepoFetchRepository() async throws {
        let dir = try makeRepo("github-fetch")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        installGitHubStub(token: nil, handler: Self.gitHubRepoStub)
        let r = try await host.server.callTool("github_repo", ["operation": .string("fetch_repository"),
                                                               "owner": .string("octocat"), "repo": .string("Hello-World"),
                                                               "query": .string("main")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Retrieved 3 files (124 bytes) from octocat/Hello-World."))
        #expect(r.resultText.contains("## File: Sources/main.swift"))
        #expect(r.resultText.contains("let a = 1"))
        #expect(r.resultText.contains("skipped as binary (1): logo.png"))
        #expect(r.resultText.contains("skipped directories (1)"))
        #expect(r.structured?["count"]?.int == 3)
    }

    @Test func gitHubRepoRejectsUnknownOperation() async throws {
        resetGitHubStub()
        let dir = try makeRepo("github-op")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        let r = try await host.server.callTool("github_repo", ["operation": .string("dance"),
                                                               "owner": .string("octocat"), "repo": .string("Hello-World")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Unsupported operation 'dance'"))
        #expect(StubGitHubProtocol.requests.isEmpty, "an unknown operation must not reach GitHub")
    }

    @Test func gitHubRepoRequiresOwnerRepoOrURL() async throws {
        let dir = try makeRepo("github-norepo")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        let r = try await host.server.callTool("github_repo", ["operation": .string("repository_info")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Provide 'owner' + 'repo'"))
    }

    @Test func gitHubRepoResolvesRepoFromURL() async throws {
        let dir = try makeRepo("github-url")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await opened(dir)
        installGitHubStub(token: nil, handler: Self.gitHubRepoStub)
        let r = try await host.server.callTool("github_repo", ["operation": .string("repository_info"),
                                                               "url": .string("https://github.com/octocat/Hello-World")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Retrieved repository metadata for octocat/Hello-World."))
    }

    // MARK: - Workspace confinement

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
