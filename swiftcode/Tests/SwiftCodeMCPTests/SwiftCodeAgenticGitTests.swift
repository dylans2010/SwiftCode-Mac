import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeAgenticGitTests {
    static let agenticGitIDs = ["git_status", "git_diff", "git_add", "git_commit", "git_checkout",
                                "git_branch", "git_merge", "git_rebase", "git_reset", "git_stash",
                                "git_pull", "git_push", "git_clone", "git_blame", "git_log",
                                "git_show", "git_tag", "git_revert", "git_worktree"]

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

    func makeRepo(_ name: String, diverged: Bool = false) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-agentic-git-\(name)-\(UUID().uuidString)")
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

    func makePlainFolder(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-agentic-git-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources/App"), withIntermediateDirectories: true)
        try "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.executableTarget(name: \"App\")])\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    func makeBareRemote(in workspace: URL, name: String = "remote.git") throws -> URL {
        _ = try Self.git(workspace, "init", "--bare", "-q", name)
        return workspace.appendingPathComponent(name)
    }

    func makeSecondCopy(_ name: String, from remote: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-agentic-git-\(name)-\(UUID().uuidString)")
        _ = try Self.git(FileManager.default.temporaryDirectory, "clone", "-q", remote.path, dest.path)
        return dest
    }

    func opened(_ dir: URL, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.agenticGitTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticGitTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(dir.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func callAgentic(_ host: SwiftCodeMCPHost, _ name: String, _ arguments: [String: AnyJSON] = [:]) async throws -> AnyJSON {
        guard let tool = host.agenticGitTools.first(where: { $0.name == name }) else {
            #expect(Bool(false), "\(name) is not in agenticGitTools")
            throw MCPToolError("not installed: \(name)")
        }
        return try await host.server.run(tool, MCPToolCall(name: name, arguments: arguments)).json
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

    @Test func agenticGitToolsListTheNineteenTools() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.agenticGitTools
        #expect(tools.map(\.name) == Self.agenticGitIDs, "agenticGitTools must be exactly the 19 slice-C Agentic git tools, in slice order")
        #expect(tools.count == 19, "no duplicate registrations")
        let expectedTitles: [String: String] = [
            "git_status": "Git Status", "git_diff": "Git Diff", "git_add": "Git Add", "git_commit": "Git Commit",
            "git_checkout": "Git Checkout", "git_branch": "Git Branch", "git_merge": "Git Merge",
            "git_rebase": "Git Rebase", "git_reset": "Git Reset", "git_stash": "Git Stash",
            "git_pull": "Git Pull", "git_push": "Git Push", "git_clone": "Git Clone", "git_blame": "Git Blame",
            "git_log": "Git Log", "git_show": "Git Show", "git_tag": "Git Tag",
            "git_revert": "Git Revert", "git_worktree": "Git Worktree",
        ]
        let expectedRequired: [String: [String]] = [
            "git_status": [], "git_diff": [], "git_add": ["files"], "git_commit": ["message"],
            "git_checkout": ["branch"], "git_branch": [], "git_merge": ["branch"], "git_rebase": ["branch"],
            "git_reset": [], "git_stash": [], "git_pull": [], "git_push": [],
            "git_clone": ["remoteURL", "destinationPath"], "git_blame": ["file"], "git_log": [],
            "git_show": ["hash"], "git_tag": [], "git_revert": ["hash"],
            "git_worktree": ["action"],
        ]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name], "\(tool.name) title")
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            #expect(tool.inputSchema["properties"]?["repositoryPath"] != nil || tool.name == "git_clone",
                    "\(tool.name) is missing the repositoryPath parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            #expect(tool.outputSchema == nil, "\(tool.name) returns Legacy's plain string, so it has no output schema")
            switch tool.name {
            case "git_status", "git_diff", "git_branch", "git_blame", "git_log", "git_show", "git_tag":
                #expect(tool.annotations.readOnly && !tool.writes, "\(tool.name) must be read-only")
            case "git_reset":
                #expect(!tool.annotations.readOnly && tool.annotations.destructive && tool.writes,
                        "git_reset is potentiallyDestructive (its Legacy default is --hard)")
            default:
                #expect(!tool.annotations.readOnly && tool.annotations.idempotent && tool.writes,
                        "\(tool.name) must be a safeMutation write tool")
            }
        }
        let installed = Set(host.agenticGitTools.map(\.name))
        host.server.tools = host.server.tools.filter { !installed.contains($0.name) } + host.agenticGitTools
        let served = host.server.tools.map(\.name)
        for id in Self.agenticGitIDs { #expect(served.contains(id), "\(id) is not installed on the server") }
    }

    @Test func statusReportsCleanAndDirty() async throws {
        let dir = try makeRepo("status")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let clean = try await callAgentic(host, "git_status")
        #expect(!clean.isToolError, "\(clean.resultText)")
        #expect(clean.firstText == "Working tree clean.")
        try writeFile(dir, "Sources/App/main.swift", "let a = 2\nprint(a)\n")
        let dirty = try await callAgentic(host, "git_status")
        #expect(!dirty.isToolError, "\(dirty.resultText)")
        #expect(dirty.firstText.contains(" M Sources/App/main.swift"), "\(dirty.firstText)")
        let viaPath = try await callAgentic(host, "git_status", ["repositoryPath": .string(dir.path)])
        #expect(!viaPath.isToolError, "\(viaPath.resultText)")
        #expect(viaPath.firstText.contains(" M Sources/App/main.swift"))
    }

    @Test func diffShowsChangesAndFiltersByFile() async throws {
        let dir = try makeRepo("diff")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let none = try await callAgentic(host, "git_diff")
        #expect(!none.isToolError, "\(none.resultText)")
        #expect(none.firstText == "No changes.")
        try writeFile(dir, "Sources/App/main.swift", "let a = 2\nprint(a)\n")
        try writeFile(dir, "Package.swift", "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App2\", targets: [.executableTarget(name: \"App\")])\n")
        let all = try await callAgentic(host, "git_diff")
        #expect(all.firstText.contains("-let a = 1") && all.firstText.contains("+let a = 2"))
        #expect(all.firstText.contains("App2"))
        let one = try await callAgentic(host, "git_diff", ["file": .string("Sources/App/main.swift")])
        #expect(one.firstText.contains("+let a = 2") && !one.firstText.contains("App2"), "\(one.firstText)")
    }

    @Test func branchListsBranches() async throws {
        let dir = try makeRepo("branches")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await callAgentic(host, "git_branch")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("main") && r.firstText.contains("feature"), "\(r.firstText)")
    }

    @Test func blameShowsLine() async throws {
        let dir = try makeRepo("blame")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await callAgentic(host, "git_blame", ["file": .string("Sources/App/main.swift")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("let a = 1"), "\(r.firstText)")
        let missing = try await callAgentic(host, "git_blame", ["file": .string("Sources/App/Nope.swift")])
        #expect(missing.isToolError && missing.firstText.contains("git blame failed"), "\(missing.firstText)")
    }

    @Test func logShowsOnelineHistory() async throws {
        let dir = try makeRepo("log", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await callAgentic(host, "git_log")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Initial commit") && r.firstText.contains("Second on main"), "\(r.firstText)")
    }

    @Test func showDisplaysCommit() async throws {
        let dir = try makeRepo("show")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let head = try Self.git(dir, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        let r = try await callAgentic(host, "git_show", ["hash": .string(head)])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Initial commit") && r.firstText.contains("let a = 1"), "\(r.firstText)")
        let bad = try await callAgentic(host, "git_show", ["hash": .string("deadbee")])
        #expect(bad.isToolError && bad.firstText.contains("git show failed"), "\(bad.firstText)")
    }

    @Test func tagListsTags() async throws {
        let dir = try makeRepo("tags")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let none = try await callAgentic(host, "git_tag")
        #expect(!none.isToolError, "\(none.resultText)")
        #expect(none.firstText == "No tags in the repository.")
        _ = try Self.git(dir, "tag", "v1.0")
        let one = try await callAgentic(host, "git_tag")
        #expect(!one.isToolError, "\(one.resultText)")
        #expect(one.firstText.contains("v1.0"), "\(one.firstText)")
    }

    @Test func statusFailsHonestlyOutsideARepository() async throws {
        let dir = try makePlainFolder("plain")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await callAgentic(host, "git_status")
        #expect(r.isToolError && r.firstText.contains("not a git repository"), "\(r.firstText)")
    }

    @Test func addAndCommitRoundTrip() async throws {
        let dir = try makeRepo("add-commit")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        try writeFile(dir, "Sources/App/New.swift", "let b = 1\n")
        let added = try await callAgentic(host, "git_add", ["files": .array([.string("Sources/App/New.swift")])])
        #expect(!added.isToolError, "\(added.resultText)")
        #expect(added.firstText == "Files added successfully")
        let committed = try await callAgentic(host, "git_commit", ["message": .string("Add New")])
        #expect(!committed.isToolError, "\(committed.resultText)")
        #expect(committed.firstText.contains("Add New"), "\(committed.firstText)")
        let log = try await callAgentic(host, "git_log")
        #expect(log.firstText.contains("Add New"))
        let noFiles = try await callAgentic(host, "git_add")
        #expect(noFiles.isToolError && noFiles.firstText.contains("Missing repositoryPath or files"))
        let noMessage = try await callAgentic(host, "git_commit")
        #expect(noMessage.isToolError && noMessage.firstText.contains("Missing repositoryPath or message"))
    }

    @Test func checkoutSwitchesBranch() async throws {
        let dir = try makeRepo("checkout")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let r = try await callAgentic(host, "git_checkout", ["branch": .string("feature")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Successfully checked out branch feature"), "\(r.firstText)")
        let current = try Self.git(dir, "branch", "--show-current").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(current == "feature")
        let bad = try await callAgentic(host, "git_checkout", ["branch": .string("--help")])
        #expect(bad.isToolError && bad.firstText.contains("Invalid branch name"))
    }

    @Test func mergeMergesFeatureBranch() async throws {
        let dir = try makeRepo("merge", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let r = try await callAgentic(host, "git_merge", ["branch": .string("feature")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(readFile(dir, "Sources/App/New.swift").contains("let b = 1"))
        #expect(readFile(dir, "Sources/App/main.swift").contains("let a = 2"))
    }

    @Test func rebaseOntoMain() async throws {
        let dir = try makeRepo("rebase", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let switched = try await callAgentic(host, "git_checkout", ["branch": .string("feature")])
        #expect(!switched.isToolError, "\(switched.resultText)")
        let r = try await callAgentic(host, "git_rebase", ["branch": .string("main")])
        #expect(!r.isToolError, "\(r.resultText)")
        let log = try Self.git(dir, "log", "--oneline")
        #expect(log.contains("Feature work") && log.contains("Second on main"), "\(log)")
    }

    @Test func resetSoftKeepsChangesAndRejectsBadMode() async throws {
        let dir = try makeRepo("reset", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let bad = try await callAgentic(host, "git_reset", ["mode": .string("--bogus"), "target": .string("HEAD")])
        #expect(bad.isToolError && bad.firstText.contains("Invalid reset mode"))
        let r = try await callAgentic(host, "git_reset", ["mode": .string("--soft"), "target": .string("HEAD~1")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(readFile(dir, "Sources/App/main.swift").contains("let a = 2"))
        let log = try Self.git(dir, "log", "--oneline")
        #expect(!log.contains("Second on main") && log.contains("Initial commit"), "\(log)")
    }

    @Test func stashPushListPopRoundTrip() async throws {
        let dir = try makeRepo("stash")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        try writeFile(dir, "Sources/App/main.swift", "let a = 9\nprint(a)\n")
        let pushed = try await callAgentic(host, "git_stash")
        #expect(!pushed.isToolError, "\(pushed.resultText)")
        #expect(readFile(dir, "Sources/App/main.swift").contains("let a = 1"), "stash push must restore the file")
        let listed = try await callAgentic(host, "git_stash", ["action": .string("list")])
        #expect(!listed.isToolError, "\(listed.resultText)")
        #expect(listed.firstText.contains("stash@{0}"), "\(listed.firstText)")
        let popped = try await callAgentic(host, "git_stash", ["action": .string("pop")])
        #expect(!popped.isToolError, "\(popped.resultText)")
        #expect(readFile(dir, "Sources/App/main.swift").contains("let a = 9"), "stash pop must restore the change")
        let bad = try await callAgentic(host, "git_stash", ["action": .string("explode")])
        #expect(bad.isToolError && bad.firstText.contains("Unsupported stash action"))
    }

    @Test func cherryPickAppliesFeatureCommit() async throws {
        let dir = try makeRepo("cherry-pick", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let hash = try Self.git(dir, "rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines)
        let r = try await host.server.callTool("git_cherry_pick", ["hash": .string(hash),
                                                                    "repositoryPath": .string(".")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(readFile(dir, "Sources/App/New.swift").contains("let b = 1"))
        let log = try Self.git(dir, "log", "--oneline")
        #expect(log.contains("Feature work"), "\(log)")
    }

    @Test func revertUndoesCommit() async throws {
        let dir = try makeRepo("revert", diverged: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let hash = try Self.git(dir, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        let r = try await callAgentic(host, "git_revert", ["hash": .string(hash)])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(readFile(dir, "Sources/App/main.swift").contains("let a = 1"), "revert must restore the file")
    }

    @Test func worktreeListsAndFailsHonestlyForAdd() async throws {
        let dir = try makeRepo("worktree")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let r = try await callAgentic(host, "git_worktree", ["action": .string("list")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains(dir.path), "\(r.firstText)")
        let add = try await callAgentic(host, "git_worktree", ["action": .string("add")])
        #expect(add.isToolError && add.firstText.contains("Git worktree add failed"), "\(add.firstText)")
        let bad = try await callAgentic(host, "git_worktree", ["action": .string("explode")])
        #expect(bad.isToolError && bad.firstText.contains("Unsupported worktree action"))
    }

    @Test func reviewRejectsCommit() async throws {
        let dir = try makeRepo("review-commit")
        defer { try? FileManager.default.removeItem(at: dir) }
        let allowHost = try await opened(dir, policy: .allow)
        try writeFile(dir, "Sources/App/New.swift", "let b = 1\n")
        let added = try await callAgentic(allowHost, "git_add", ["files": .array([.string("Sources/App/New.swift")])])
        #expect(!added.isToolError, "\(added.resultText)")
        let reviews = Reviews()
        let reviewHost = try await opened(dir, policy: .review { c in reviews.changes.append(c); return reviews.accept })
        let rejected = try await callAgentic(reviewHost, "git_commit", ["message": .string("Add New")])
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        #expect(reviews.changes.first?.tool == "git_commit")
        let log = try Self.git(dir, "log", "--oneline")
        #expect(!log.contains("Add New"), "rejected commit must not land")
        reviews.accept = true
        let committed = try await callAgentic(reviewHost, "git_commit", ["message": .string("Add New")])
        #expect(!committed.isToolError, "\(committed.resultText)")
    }

    @Test func readOnlyModeRefusesWritesButAllowsReads() async throws {
        let dir = try makeRepo("readonly")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let refused = try await callAgentic(host, "git_add", ["files": .array([.string("Sources/App/main.swift")])])
        #expect(refused.isToolError && refused.firstText.contains("read-only"), "\(refused.firstText)")
        let status = try await callAgentic(host, "git_status")
        #expect(!status.isToolError, "\(status.resultText)")
        #expect(status.firstText == "Working tree clean.")
        let stashList = try await callAgentic(host, "git_stash", ["action": .string("list")])
        #expect(stashList.isToolError && stashList.firstText.contains("read-only"), "\(stashList.firstText)")
    }

    @Test func repositoryPathOutsideWorkspaceIsRefused() async throws {
        let dir = try makeRepo("repo-path")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir)
        let r = try await callAgentic(host, "git_status", ["repositoryPath": .string("../outside")])
        #expect(r.isToolError && r.firstText.contains("outside the workspace"), "\(r.firstText)")
    }

    @Test func remotePullPushCloneRoundTripOverLocalBareRemote() async throws {
        let dir = try makeRepo("remote-roundtrip")
        defer { try? FileManager.default.removeItem(at: dir) }
        let remote = try makeBareRemote(in: dir)
        _ = try Self.git(dir, "remote", "add", "origin", remote.path)
        _ = try Self.git(dir, "push", "-q", "-u", "origin", "main")
        let host = try await opened(dir, policy: .allow)
        try writeFile(dir, "Sources/App/Pushed.swift", "let p = 1\n")
        _ = try Self.git(dir, "add", "-A")
        _ = try Self.git(dir, "commit", "-qm", "Pushed commit")
        let pushed = try await callAgentic(host, "git_push")
        #expect(!pushed.isToolError, "\(pushed.resultText)")
        #expect(pushed.firstText.contains("Push successful"), "\(pushed.firstText)")
        let remoteLog = try Self.git(remote, "log", "--oneline", "main")
        #expect(remoteLog.contains("Pushed commit"), "\(remoteLog)")
        let other = try makeSecondCopy("remote-other", from: remote)
        defer { try? FileManager.default.removeItem(at: other) }
        try writeFile(other, "Sources/App/Pulled.swift", "let q = 1\n")
        _ = try Self.git(other, "add", "-A")
        _ = try Self.git(other, "commit", "-qm", "Pulled commit")
        _ = try Self.git(other, "push", "-q", "origin", "main")
        let pulled = try await callAgentic(host, "git_pull")
        #expect(!pulled.isToolError, "\(pulled.resultText)")
        #expect(pulled.firstText.contains("Successfully pulled changes"), "\(pulled.firstText)")
        #expect(readFile(dir, "Sources/App/Pulled.swift").contains("let q = 1"))
        let cloned = try await callAgentic(host, "git_clone",
                                           ["remoteURL": .string(remote.path),
                                            "destinationPath": .string("cloned")])
        #expect(!cloned.isToolError, "\(cloned.resultText)")
        #expect(cloned.firstText.contains("Successfully cloned"), "\(cloned.firstText)")
        #expect(cloned.structured?["output"]?.string?.contains("Cloning into") == true, "\(cloned.resultText)")
        #expect(readFile(dir, "cloned/Sources/App/main.swift").contains("let a = 1"))
    }

    @Test func remoteURLPolicyRejectsOtherSchemesAndOutsidePaths() async throws {
        let dir = try makeRepo("remote-policy")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        for url in ["ftp://example.invalid/repo.git",
                    "ssh://git@example.invalid/repo.git",
                    "git://example.invalid/repo.git",
                    "https://user:secret@example.invalid/repo.git"] {
            let r = try await callAgentic(host, "git_clone",
                                          ["remoteURL": .string(url),
                                           "destinationPath": .string("clone-rejected")])
            #expect(r.isToolError && r.firstText.contains("Unsupported remote URL"), "\(url): \(r.firstText)")
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("clone-rejected").path),
                    "a rejected clone must not create anything: \(url)")
        }
        let outside = try await callAgentic(host, "git_clone",
                                            ["remoteURL": .string("/tmp/swiftcode-outside-remote-\(UUID().uuidString).git"),
                                             "destinationPath": .string("clone-outside")])
        #expect(outside.isToolError && outside.firstText.contains("outside the workspace"), "\(outside.firstText)")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("clone-outside").path))
        let ssh = try await callAgentic(host, "git_clone",
                                        ["remoteURL": .string("git@nonexistent.invalid:owner/repo.git"),
                                         "destinationPath": .string("clone-ssh")])
        #expect(ssh.isToolError && ssh.firstText.contains("Git clone failed"), "\(ssh.firstText)")
        #expect(!ssh.firstText.contains("Unsupported remote URL"), "\(ssh.firstText)")
    }

    @Test func remoteToolsRespectApprovalAndReadOnlyMode() async throws {
        let dir = try makeRepo("remote-approval")
        defer { try? FileManager.default.removeItem(at: dir) }
        let remote = try makeBareRemote(in: dir)
        _ = try Self.git(dir, "remote", "add", "origin", remote.path)
        _ = try Self.git(dir, "push", "-q", "-u", "origin", "main")
        let reviews = Reviews()
        let reviewHost = try await opened(dir, policy: .review { c in reviews.changes.append(c); return reviews.accept })
        let refused = try await callAgentic(reviewHost, "git_push")
        #expect(refused.isToolError && refused.firstText == MCPServer.rejectedMessage)
        #expect(reviews.changes.first?.tool == "git_push")
        let remoteLog = try Self.git(remote, "log", "--oneline", "main")
        #expect(remoteLog.contains("Initial commit") && !remoteLog.contains("Pushed commit"), "\(remoteLog)")
        reviews.accept = true
        let pushed = try await callAgentic(reviewHost, "git_push")
        #expect(!pushed.isToolError, "\(pushed.resultText)")
        let readOnlyHost = try await opened(dir)
        let refusedPull = try await callAgentic(readOnlyHost, "git_pull")
        #expect(refusedPull.isToolError && refusedPull.firstText.contains("read-only"), "\(refusedPull.firstText)")
        let refusedClone = try await callAgentic(readOnlyHost, "git_clone",
                                                 ["remoteURL": .string(remote.path),
                                                  "destinationPath": .string("clone-ro")])
        #expect(refusedClone.isToolError && refusedClone.firstText.contains("read-only"), "\(refusedClone.firstText)")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("clone-ro").path))
    }

    @Test func remoteToolsFailHonestlyWithNoRemote() async throws {
        let dir = try makeRepo("remote-noremote")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try await opened(dir, policy: .allow)
        let pull = try await callAgentic(host, "git_pull")
        #expect(pull.isToolError && pull.firstText.contains("Git pull failed"), "\(pull.firstText)")
        let push = try await callAgentic(host, "git_push")
        #expect(push.isToolError && push.firstText.contains("Git push failed"), "\(push.firstText)")
        let clone = try await callAgentic(host, "git_clone",
                                          ["remoteURL": .string("not-a-repo"),
                                           "destinationPath": .string("clone-nope")])
        #expect(clone.isToolError && clone.firstText.contains("Git clone failed"), "\(clone.firstText)")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("clone-nope").path))
    }

    @Test func gitHubHTTPSPathAndCredentialSeedingTolerateNoHelper() async throws {
        #expect(SwiftCodeMCPHost.gitHubHTTPSPath("https://github.com/dylans2010/SwiftCode-Mac") == "dylans2010/SwiftCode-Mac")
        #expect(SwiftCodeMCPHost.gitHubHTTPSPath("https://github.com") == "")
        #expect(SwiftCodeMCPHost.gitHubHTTPSPath("https://GITHUB.COM/dylans2010/repo.git") == "dylans2010/repo.git")
        #expect(SwiftCodeMCPHost.gitHubHTTPSPath("git@github.com:dylans2010/SwiftCode-Mac") == nil)
        #expect(SwiftCodeMCPHost.gitHubHTTPSPath("https://user:token@github.com/dylans2010/repo.git") == nil)
        #expect(SwiftCodeMCPHost.gitHubHTTPSPath("https://example.com/dylans2010/repo.git") == nil)
        SwiftCodeMCPHost.agenticGitTestSecretStore = MemorySecretStore()
        defer { SwiftCodeMCPHost.agenticGitTestSecretStore = nil }
        try SwiftCodeMCPHost.agenticGitTestSecretStore?.write(Data("test-token".utf8), for: SecretAccount.githubToken)
        let dir = try makeRepo("remote-seeding")
        defer { try? FileManager.default.removeItem(at: dir) }
        let remote = try makeBareRemote(in: dir)
        _ = try Self.git(dir, "remote", "add", "origin", remote.path)
        _ = try Self.git(dir, "push", "-q", "-u", "origin", "main")
        let host = try await opened(dir, policy: .allow)
        let cloned = try await callAgentic(host, "git_clone",
                                           ["remoteURL": .string(remote.path),
                                            "destinationPath": .string("cloned")])
        #expect(!cloned.isToolError, "\(cloned.resultText)")
        #expect(readFile(dir, "cloned/Sources/App/main.swift").contains("let a = 1"))
    }
}
