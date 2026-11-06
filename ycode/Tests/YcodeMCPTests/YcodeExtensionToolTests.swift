import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

/// `use_extension` wired to the Extensions v2 host (Wave 11 Slice C).
///
/// Behaviour source: `specs/ide/extensions-platform.md` §7.2 (the
/// 11-action contract: confirm rule, limit clamping, 8,000-char cap,
/// error mapping) and §5.4 (the single Wave 2 approval gate).
///
/// The tests are black-box through the server (the Wave 4 shape:
/// assertions on the tool RESULT, never on internals) because this
/// test target does not depend on `YcodeExtensions` — the host is
/// reached only through the handler. The sample-plugin fixture tests
/// (list/details/diagnostics against a registered sample plugin)
/// therefore live with the host's own tests instead; what this file
/// covers black-box is: validation, the `confirm: true` rule,
/// `run_xcode_command`'s file + selection validation and its
/// sort-lines end-to-end behaviour (the sort-lines command is
/// registered by the manager's init, so it is always present), and
/// the not-installed / empty answers for unknown extensions.
///
/// Assertions use `firstText` (never exact `resultText ==`):
/// `MCPToolResult.structured(_:summary:)` emits two text blocks.
@MainActor
@Suite(.serialized) struct YcodeExtensionToolTests {
    /// Opens a copy of Greeter and installs the ported terminal tools
    /// on the server (same shape as `YcodeTerminalToolsTests.opened`).
    /// Defaults to `.allow`: `use_extension` is `writes: true`, so
    /// the read-only policy refuses it before it runs.
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.terminalTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.terminalTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Writes a fixture file directly (not through a tool under test).
    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Host-independent validation

    @Test func unknownActionFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_extension", ["action": .string("explode")])
        #expect(r.isToolError && r.firstText.contains("Unknown or missing action"))
    }

    @Test func mutatingActionsRequireConfirmTrue() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // The confirm check fires before the extension/host lookups,
        // so these need no installed extension to prove the rule.
        let cases: [[String: AnyJSON]] = [
            ["action": .string("activate"), "extensionId": .string("x.y")],
            ["action": .string("execute"), "extensionId": .string("x.y"), "command": .string("c")],
            ["action": .string("run_xcode_command"), "extensionId": .string("x.y"),
             "command": .string("com.swiftcode.xcode.sortLines"), "file": .string("Lines.txt")],
            ["action": .string("enable"), "extensionId": .string("x.y")],
            ["action": .string("disable"), "extensionId": .string("x.y")],
        ]
        for args in cases {
            let missing = try await host.server.callTool("use_extension", args)
            #expect(missing.isToolError && missing.firstText.contains("requires confirm: true"), "\(args)")
            var denied = args
            denied["confirm"] = .bool(false)
            let explicit = try await host.server.callTool("use_extension", denied)
            #expect(explicit.isToolError && explicit.firstText.contains("requires confirm: true"), "\(denied)")
        }
        // `deactivate` needs neither: it is classified read-only
        // (spec §5.4), so it passes the confirm check and reaches the
        // host, which deactivates (a no-op for an unknown id).
        let deact = try await host.server.callTool("use_extension", ["action": .string("deactivate"),
                                                                     "extensionId": .string("x.y")])
        #expect(!deact.isToolError && deact.firstText.contains("Deactivated x.y."), "\(deact.firstText)")
    }

    @Test func extensionIdIsRequiredExceptForListActions() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        for action in ["details", "list_commands", "activate", "deactivate", "execute", "enable", "disable", "diagnostics"] {
            var args: [String: AnyJSON] = ["action": .string(action)]
            if action == "execute" { args["command"] = .string("c") }
            if ["activate", "execute", "enable", "disable"].contains(action) { args["confirm"] = .bool(true) }
            let r = try await host.server.callTool("use_extension", args)
            #expect(r.isToolError && r.firstText.contains("requires 'extensionId'"), "\(action): \(r.firstText)")
        }
    }

    @Test func commandIsRequiredForExecuteAndRunXcodeCommand() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let exec = try await host.server.callTool("use_extension", ["action": .string("execute"),
                                                                    "extensionId": .string("x.y"), "confirm": .bool(true)])
        #expect(exec.isToolError && exec.firstText.contains("requires 'command'"))
        let run = try await host.server.callTool("use_extension", ["action": .string("run_xcode_command"),
                                                                   "extensionId": .string("x.y"), "confirm": .bool(true),
                                                                   "file": .string("Lines.txt")])
        #expect(run.isToolError && run.firstText.contains("requires 'command'"))
    }

    // MARK: - `run_xcode_command` file + selection validation (no host needed)

    @Test func runXcodeCommandRejectsAbsoluteAndEscapingFiles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let base: [String: AnyJSON] = ["action": .string("run_xcode_command"), "extensionId": .string("x.y"),
                                       "command": .string("com.swiftcode.xcode.sortLines"), "confirm": .bool(true)]
        var absolute = base
        absolute["file"] = .string("/etc/passwd")
        let a = try await host.server.callTool("use_extension", absolute)
        #expect(a.isToolError && a.firstText.contains("absolute paths are rejected"), "\(a.firstText)")
        var escaping = base
        escaping["file"] = .string("../outside.swift")
        let e = try await host.server.callTool("use_extension", escaping)
        #expect(e.isToolError && e.firstText.contains("outside the workspace"), "\(e.firstText)")
        var missing = base
        missing["file"] = .string("Nope.swift")
        let m = try await host.server.callTool("use_extension", missing)
        #expect(m.isToolError && m.firstText.contains("Cannot read 'Nope.swift'"), "\(m.firstText)")
    }

    @Test func runXcodeCommandValidatesSelectionBounds() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "Lines.txt", "cherry\nbanana\napple\n")
        let host = try await opened(sample)
        func call(selection: [String: AnyJSON]) async throws -> AnyJSON {
            try await host.server.callTool("use_extension",
                                           ["action": .string("run_xcode_command"), "extensionId": .string("x.y"),
                                            "command": .string("com.swiftcode.xcode.sortLines"), "confirm": .bool(true),
                                            "file": .string("Lines.txt"), "selection": .object(selection)])
        }
        // Lines.txt is 3 lines + a trailing empty line ("cherry\nbanana\napple\n").
        let pastEnd = try await call(selection: ["startLine": .int(0), "startColumn": .int(0),
                                                 "endLine": .int(99), "endColumn": .int(0)])
        #expect(pastEnd.isToolError && pastEnd.firstText.contains("out of bounds"), "\(pastEnd.firstText)")
        let pastColumn = try await call(selection: ["startLine": .int(0), "startColumn": .int(0),
                                                    "endLine": .int(0), "endColumn": .int(999)])
        #expect(pastColumn.isToolError && pastColumn.firstText.contains("out of bounds"), "\(pastColumn.firstText)")
        let reversed = try await call(selection: ["startLine": .int(2), "startColumn": .int(0),
                                                  "endLine": .int(0), "endColumn": .int(0)])
        #expect(reversed.isToolError && reversed.firstText.contains("starts after it ends"), "\(reversed.firstText)")
    }

    // MARK: - Real host, black-box

    @Test func listAnswersWithActionAndCount() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_extension", ["action": .string("list")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["action"]?.string == "list")
        #expect((r.structured?["count"]?.int ?? -1) >= 0)
        // `limit` clamps: 0 becomes 1, 999 becomes 200 — either way
        // the call succeeds.
        let clamped = try await host.server.callTool("use_extension", ["action": .string("list"), "limit": .int(0)])
        #expect(!clamped.isToolError, "\(clamped.resultText)")
        // Deviation from spec §7.2's NSNumber truncation, forced by
        // Ycode's server-wide schema validation (`argumentProblem`
        // runs in `run()` before the handler): a non-whole numeric
        // limit never reaches the handler — it fails as a type error.
        // Whole doubles (3.0) still coerce through `.int`.
        let fractional = try await host.server.callTool("use_extension", ["action": .string("list"), "limit": .double(12.7)])
        #expect(fractional.isToolError && fractional.firstText.contains("must be of type integer"), "\(fractional.firstText)")
    }

    @Test func listXcodeCommandsIncludesSortLines() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_extension", ["action": .string("list_xcode_commands")])
        #expect(!r.isToolError, "\(r.resultText)")
        // The manager's init registers the sort-lines command, and the
        // handler touches the manager before reading the registry.
        #expect(r.firstText.contains("com.swiftcode.xcode.sortLines"))
    }

    @Test func unknownExtensionActionsFailNotInstalled() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        for args in [
            ["action": .string("details"), "extensionId": .string("no.such")],
            ["action": .string("list_commands"), "extensionId": .string("no.such")],
            ["action": .string("activate"), "extensionId": .string("no.such"), "confirm": .bool(true)],
            ["action": .string("execute"), "extensionId": .string("no.such"), "command": .string("c"), "confirm": .bool(true)],
            ["action": .string("enable"), "extensionId": .string("no.such"), "confirm": .bool(true)],
            ["action": .string("disable"), "extensionId": .string("no.such"), "confirm": .bool(true)],
        ] as [[String: AnyJSON]] {
            let r = try await host.server.callTool("use_extension", args)
            #expect(r.isToolError && r.firstText.contains("is not installed"), "\(args): \(r.firstText)")
        }
        // `diagnostics` does not guard on installed (spec §7.2): an
        // unknown id simply has no entries.
        let d = try await host.server.callTool("use_extension", ["action": .string("diagnostics"),
                                                                 "extensionId": .string("no.such")])
        #expect(!d.isToolError && d.firstText.contains("No diagnostics recorded for no.such."), "\(d.firstText)")
    }

    @Test func runXcodeCommandSortsSelectedLines() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "Lines.txt", "cherry\nbanana\napple\n")
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_extension",
                                               ["action": .string("run_xcode_command"),
                                                "extensionId": .string("x.y"),
                                                "command": .string("com.swiftcode.xcode.sortLines"),
                                                "confirm": .bool(true), "file": .string("Lines.txt"),
                                                "selection": .object(["startLine": .int(0), "startColumn": .int(0),
                                                                      "endLine": .int(2), "endColumn": .int(5)])])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["changed"]?.bool == true)
        #expect(r.firstText.contains("3 lines"))
        let onDisk = sample.read("Lines.txt")
        #expect(onDisk.components(separatedBy: .newlines).prefix(3) == ["apple", "banana", "cherry"])
        // A second run over the already-sorted lines changes nothing
        // and writes nothing.
        let again = try await host.server.callTool("use_extension",
                                                   ["action": .string("run_xcode_command"),
                                                    "extensionId": .string("x.y"),
                                                    "command": .string("com.swiftcode.xcode.sortLines"),
                                                    "confirm": .bool(true), "file": .string("Lines.txt"),
                                                    "selection": .object(["startLine": .int(0), "startColumn": .int(0),
                                                                          "endLine": .int(2), "endColumn": .int(5)])])
        #expect(!again.isToolError, "\(again.resultText)")
        #expect(again.structured?["changed"]?.bool == false)
        #expect(again.firstText.contains("made no changes"))
    }

    @Test func runXcodeCommandUnknownCommandListsRegistered() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "Lines.txt", "b\na\n")
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_extension",
                                               ["action": .string("run_xcode_command"),
                                                "extensionId": .string("x.y"),
                                                "command": .string("com.swiftcode.xcode.nope"),
                                                "confirm": .bool(true), "file": .string("Lines.txt")])
        #expect(r.isToolError && r.firstText.contains("Unknown Xcode command"))
        #expect(r.firstText.contains("com.swiftcode.xcode.sortLines"))
        #expect(sample.read("Lines.txt") == "b\na\n", "a throwing command leaves the file untouched")
    }
}
