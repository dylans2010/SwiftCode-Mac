import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeExtensionToolTests {
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.terminalTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.terminalTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

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

    @Test func listAnswersWithActionAndCount() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_extension", ["action": .string("list")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["action"]?.string == "list")
        #expect((r.structured?["count"]?.int ?? -1) >= 0)
        let clamped = try await host.server.callTool("use_extension", ["action": .string("list"), "limit": .int(0)])
        #expect(!clamped.isToolError, "\(clamped.resultText)")
        let fractional = try await host.server.callTool("use_extension", ["action": .string("list"), "limit": .double(12.7)])
        #expect(fractional.isToolError && fractional.firstText.contains("must be of type integer"), "\(fractional.firstText)")
    }

    @Test func listXcodeCommandsIncludesSortLines() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_extension", ["action": .string("list_xcode_commands")])
        #expect(!r.isToolError, "\(r.resultText)")
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
