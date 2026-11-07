import Foundation
import Testing
import SwiftCodeAssistant
import SwiftCodeIDECore
@testable import SwiftCodeMCP

@MainActor
@Suite(.serialized) struct CorrectnessGapTests {
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.fileWritingTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.fileWritingTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func resultText(_ result: MCPToolResult) -> String {
        result.content.compactMap { $0["text"]?.string }.first ?? ""
    }

    func put(_ sample: TempSample, _ rel: String, _ text: String) throws {
        let url = sample.url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func fileCreateReportsDiffForNewFile() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let created = try await host.server.callTool("file_create", ["path": .string("DiffTests/new.txt"),
                                                                    "content": .string("hello\nworld\n")])
        #expect(!created.isToolError, "\(created.resultText)")
        let diff = created.structured?["diff"]?.string ?? ""
        #expect(diff.contains("--- a/DiffTests/new.txt"))
        #expect(diff.contains("+hello") && diff.contains("+world"))
        #expect(!diff.contains("-hello"))
    }

    @Test func fileCreateOverwriteAndCodeReplaceReportDiffs() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        _ = try await host.server.callTool("file_create", ["path": .string("DiffTests/a.txt"),
                                                         "content": .string("one\ntwo\nthree\nfour\nfive\n")])
        let overwritten = try await host.server.callTool("file_create", ["path": .string("DiffTests/a.txt"),
                                                                        "content": .string("one\nTWO\nthree\nfour\nfive\n"),
                                                                        "overwrite": .bool(true)])
        #expect(!overwritten.isToolError, "\(overwritten.resultText)")
        let overwriteDiff = overwritten.structured?["diff"]?.string ?? ""
        #expect(overwriteDiff.contains("-two") && overwriteDiff.contains("+TWO"))
        #expect(!overwriteDiff.contains("-three") && !overwriteDiff.contains("-five"))
        let replaced = try await host.server.callTool("code_replace", ["path": .string("DiffTests/a.txt"),
                                                                      "target": .string("three"),
                                                                      "replacement": .string("THREE")])
        #expect(!replaced.isToolError, "\(replaced.resultText)")
        let replaceDiff = replaced.structured?["diff"]?.string ?? ""
        #expect(replaceDiff.contains("-three") && replaceDiff.contains("+THREE"))
        #expect(replaceDiff.contains("@@ -"))
    }

    @Test func aliasTable() {
        let empty: Set<String> = []
        #expect(MCPParameterAliases.normalized(["filePath": .string("a.txt")], declaredProperties: empty) == ["path": .string("a.txt")])
        #expect(MCPParameterAliases.normalized(["file_path": .string("a.txt")], declaredProperties: empty) == ["path": .string("a.txt")])
        #expect(MCPParameterAliases.normalized(["targetFile": .string("a.txt")], declaredProperties: empty) == ["path": .string("a.txt")])
        #expect(MCPParameterAliases.normalized(["file": .string("a.txt")], declaredProperties: empty) == ["path": .string("a.txt")])
        #expect(MCPParameterAliases.normalized(["csvPath": .string("a.csv")], declaredProperties: empty) == ["path": .string("a.csv")])
        #expect(MCPParameterAliases.normalized(["file_content": .string("body")], declaredProperties: empty) == ["content": .string("body")])
        #expect(MCPParameterAliases.normalized(["code": .string("body")], declaredProperties: empty) == ["content": .string("body")])
        #expect(MCPParameterAliases.normalized(["old_string": .string("x"), "new_string": .string("y")], declaredProperties: empty)
                == ["target": .string("x"), "replacement": .string("y")])
        #expect(MCPParameterAliases.normalized(["find": .string("x"), "replace": .string("y")], declaredProperties: empty)
                == ["target": .string("x"), "replacement": .string("y")])
        #expect(MCPParameterAliases.normalized(["cmd": .string("ls")], declaredProperties: empty) == ["command": .string("ls")])
    }

    @Test func aliasDoesNotOverrideCanonical() {
        let empty: Set<String> = []
        #expect(MCPParameterAliases.normalized(["path": .string("a"), "filePath": .string("b")], declaredProperties: empty)
                == ["path": .string("a")])
        #expect(MCPParameterAliases.normalized(["path": .string("a"), "filePath": .null], declaredProperties: empty)
                == ["path": .string("a")])
    }

    @Test func aliasDoesNotSwallowDeclaredProperties() {
        #expect(MCPParameterAliases.normalized(["code": .string("x")], declaredProperties: ["code"])
                == ["code": .string("x")])
        #expect(MCPParameterAliases.normalized(["data": .string("x")], declaredProperties: ["data"])
                == ["data": .string("x")])
        #expect(MCPParameterAliases.normalized(["bogus": .int(1)], declaredProperties: []) == ["bogus": .int(1)])
    }

    @Test func safeUndoRestoresPreviousContent() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try put(sample, "UndoTests/a.txt", "v2\n")
        SafeUndoJournal.shared.record(workspaceRoot: sample.url, relativePath: "UndoTests/a.txt", original: "v1\n", tool: "file_write")
        let result = try await host.correctnessSafeUndo(MCPToolCall(name: "safe_undo", arguments: [:]))
        #expect(!result.isError)
        #expect(sample.read("UndoTests/a.txt") == "v1\n")
        #expect(resultText(result).contains("Undid file_write"))
        do {
            _ = try await host.correctnessSafeUndo(MCPToolCall(name: "safe_undo", arguments: [:]))
            #expect(Bool(false), "expected safe_undo to fail with an empty journal")
        } catch let error as MCPToolError {
            #expect(error.message.contains("no agent modification"))
        }
    }

    @Test func safeUndoRemovesFileThatDidNotExist() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try put(sample, "UndoTests/new.txt", "fresh\n")
        SafeUndoJournal.shared.record(workspaceRoot: sample.url, relativePath: "UndoTests/new.txt", original: nil, tool: "file_create")
        let result = try await host.correctnessSafeUndo(MCPToolCall(name: "safe_undo", arguments: [:]))
        #expect(!result.isError)
        #expect(!FileManager.default.fileExists(atPath: sample.path("UndoTests/new.txt")))
        #expect(resultText(result).contains("did not exist"))
    }

    @Test func safeUndoRefusesUnrecordedEntry() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try put(sample, "UndoTests/big.txt", "big\n")
        SafeUndoJournal.shared.record(workspaceRoot: sample.url, relativePath: "UndoTests/big.txt", original: nil,
                                      unrecorded: true, tool: "file_write")
        do {
            _ = try await host.correctnessSafeUndo(MCPToolCall(name: "safe_undo", arguments: [:]))
            #expect(Bool(false), "expected safe_undo to refuse an unrecorded entry")
        } catch let error as MCPToolError {
            #expect(error.message.contains("was not recorded"))
        }
        #expect(sample.read("UndoTests/big.txt") == "big\n")
    }

    @Test func sessionProgressCountsRealPlans() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let tasks = [
            AgenticPlanningTask(id: UUID().uuidString, title: "Do A", status: "completed"),
            AgenticPlanningTask(id: UUID().uuidString, title: "Do B", status: "completed"),
            AgenticPlanningTask(id: UUID().uuidString, title: "Do C", status: "in_progress"),
            AgenticPlanningTask(id: UUID().uuidString, title: "Do D", status: "failed", detail: "boom"),
            AgenticPlanningTask(id: UUID().uuidString, title: "Do E", status: "queued"),
        ]
        _ = AgenticPlanningPlanStore.shared.create(workspace: sample.url.path, goal: "Test goal", tasks: tasks)
        let result = try host.correctnessSessionProgress(MCPToolCall(name: "session_progress_report", arguments: [:]))
        #expect(!result.isError)
        #expect(result.structured?["phaseCount"]?.int == 5)
        #expect(result.structured?["completed"]?.int == 2)
        #expect(result.structured?["inProgress"]?.int == 1)
        #expect(result.structured?["failed"]?.int == 1)
        #expect(result.structured?["pending"]?.int == 1)
        #expect(resultText(result).contains("2 of 5 phases completed"))
        #expect(resultText(result).contains("Do C"))
        #expect(resultText(result).contains("Do D"))
    }

    @Test func sessionProgressWithNoPlansIsZero() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let result = try host.correctnessSessionProgress(MCPToolCall(name: "session_progress_report", arguments: [:]))
        #expect(result.structured?["phaseCount"]?.int == 0)
        #expect(resultText(result).contains("No engineering phases are registered"))
    }

    static let astFixture = """
        import Foundation

        /// A thing.
        class Engine: NSObject {
            var name: String = ""
            func start(mode: String) -> Bool { true }
        }

        struct Config {
            let retries: Int
        }

        enum State {
            case idle
            case running
        }

        let note = "class Fake {}"
        """

    @Test func astInspectorFindsRealDeclarations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try put(sample, "ASTTests/Fixture.swift", Self.astFixture)
        let result = try host.correctnessSwiftASTInspector(MCPToolCall(name: "swift_ast_inspector",
                                                                       arguments: ["path": .string("ASTTests/Fixture.swift")]))
        #expect(!result.isError)
        let text = resultText(result)
        #expect(text.contains("[class] Engine (line 4)"))
        #expect(text.contains("NSObject"))
        #expect(text.contains("[func] start (line 6)"))
        #expect(text.contains("(mode: String) -> Bool"))
        #expect(text.contains("[struct] Config (line 9)"))
        #expect(text.contains("[enum] State (line 13)"))
        #expect(text.contains("Imports: Foundation."))
        #expect(!text.contains("Fake"))
    }

    @Test func astInspectorSymbolFilter() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try put(sample, "ASTTests/Fixture.swift", Self.astFixture)
        let result = try host.correctnessSwiftASTInspector(MCPToolCall(name: "swift_ast_inspector",
                                                                       arguments: ["path": .string("ASTTests/Fixture.swift"),
                                                                                   "symbol": .string("start")]))
        #expect(resultText(result).contains("start"))
        #expect(!resultText(result).contains("Config"))
    }

    @Test func astInspectorReportsParseErrors() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try put(sample, "ASTTests/Broken.swift", "struct Broken {\n    var x: Int\n")
        let result = try host.correctnessSwiftASTInspector(MCPToolCall(name: "swift_ast_inspector",
                                                                       arguments: ["path": .string("ASTTests/Broken.swift")]))
        #expect(resultText(result).contains("parse errors"))
        #expect(resultText(result).contains("[struct] Broken"))
    }

    @Test func astEngineDirect() {
        let inspection = SwiftASTInspection.inspect(source: Self.astFixture)
        #expect(!inspection.hasError)
        #expect(inspection.imports == ["Foundation"])
        #expect(inspection.kind(of: "Engine") == "class")
        #expect(inspection.kind(of: "start") == "func")
        #expect(inspection.kind(of: "Fake") == nil)
        let broken = SwiftASTInspection.inspect(source: "struct Broken {\n    var x: Int\n")
        #expect(broken.hasError)
    }

    static let renameFixture = """
        import Foundation

        struct Widget {
            var title: String
            func greet() -> String { "Widget" }
        }

        // Widget in a comment
        let widget = Widget()
        let label = "Widget"
        """

    @Test func renameEngineDirect() {
        let result = SymbolRenameEngine.rename(source: Self.renameFixture, oldName: "Widget", newName: "Gadget")
        #expect(result.replacements == 2)
        #expect(result.skipped == 3)
        #expect(result.declarationFound && result.declarationKind == "struct")
        #expect(result.updated.contains("struct Gadget"))
        #expect(result.updated.contains("Gadget()"))
        #expect(result.updated.contains("\"Widget\""))
        #expect(result.updated.contains("// Widget in a comment"))
        #expect(result.updated.contains("import Foundation"))
    }

    @Test func renameProjectIsTokenAware() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try put(sample, "RenameTests/Widget.swift", Self.renameFixture)
        let result = try await host.correctnessRenameSymbolProject(MCPToolCall(name: "symbol_rename_project",
                                                                              arguments: ["oldName": .string("Widget"),
                                                                                          "newName": .string("Gadget")]))
        #expect(!result.isError, "\(resultText(result))")
        #expect(result.structured?["replacementCount"]?.int == 2)
        #expect(result.structured?["changedFileCount"]?.int == 1)
        let after = sample.read("RenameTests/Widget.swift")
        #expect(after.contains("struct Gadget") && after.contains("Gadget()"))
        #expect(after.contains("\"Widget\"") && after.contains("// Widget in a comment"))
        #expect(resultText(result).contains("3 occurrence(s) inside strings"))
    }

    @Test func renameWithOnlyStringOccurrencesChangesNothing() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try put(sample, "RenameTests/OnlyString.swift", "let label = \"Widget\"\n")
        let result = try await host.correctnessRenameSymbolProject(MCPToolCall(name: "symbol_rename_project",
                                                                              arguments: ["oldName": .string("Widget"),
                                                                                          "newName": .string("Gadget")]))
        #expect(!result.isError)
        #expect(result.structured?["replacementCount"]?.int == 0)
        #expect(sample.read("RenameTests/OnlyString.swift") == "let label = \"Widget\"\n")
        #expect(resultText(result).contains("only inside strings"))
    }
}
