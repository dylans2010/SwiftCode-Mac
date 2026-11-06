import Foundation
import Testing
import SwiftCodeAssistant
import SwiftCodeIDECore
@testable import SwiftCodeMCP

/// The ported Legacy search / code-navigation tools against
/// `Samples/AgentSamples/Greeter` (a copy). Fixture facts used below
/// (verified from the sample): the workspace has 5 Swift files
/// (`Package.swift`, `Sources/Greeter/Greeter.swift`,
/// `Sources/greet/main.swift`, `Previews/GreetingView.swift`,
/// `Tests/GreeterTests/GreeterTests.swift`) and one `.xcstrings` file.
/// `Greeter.swift` is 14 lines plus a trailing newline: `struct
/// Greeter` at line 2, `var salutation` at line 4, `init` at line 6,
/// `func greeting` at line 11. `main.swift` imports `Greeter` and
/// calls `Greeter().greeting(for:)` at line 4.
/// `GreetingView.swift` is `struct GreetingView: View` at line 4.
/// `GreeterTests.swift` is `final class GreeterTests: XCTestCase` at
/// line 4. `Package.swift` imports `PackageDescription`.
@MainActor
@Suite(.serialized) struct SwiftCodeSearchToolsTests {
    static let searchIDs = ["call_hierarchy", "code_summary", "dependency_graph", "extract_code_symbols", "import_graph",
                            "protocol_conformance_list", "search_regex", "search_skills", "search_symbol", "search_text",
                            "semantic_query_engine", "source_graph_builder", "symbol_move_file", "symbol_reference_graph",
                            "symbol_rename_project", "type_hierarchy"]

    /// Opens a copy of Greeter and installs the ported search tools on
    /// the server (same shape as Wave 2's `opened`; the coordinator
    /// wires `searchTools` into `installTools()`).
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        // Filter-first (Wave 2 shape): `installTools()` already wires
        // `searchTools`, so a plain `+=` would register them twice.
        let ported = Set(host.searchTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.searchTools
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

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.searchTools
        #expect(tools.map(\.name) == Self.searchIDs)
        let expectedTitles: [String: String] = [
            "call_hierarchy": "Call Hierarchy", "code_summary": "Code Summary", "dependency_graph": "Dependency Graph",
            "extract_code_symbols": "Extract Code Symbols", "import_graph": "Import Graph",
            "protocol_conformance_list": "Protocol Conformance List", "search_regex": "Regex Search",
            "search_skills": "Search Agent Skills", "search_symbol": "Symbol Search", "search_text": "Search Text",
            "semantic_query_engine": "Semantic Source Query Engine", "source_graph_builder": "Source Graph Builder",
            "symbol_move_file": "Move Symbol Across Files", "symbol_reference_graph": "Symbol Reference Graph",
            "symbol_rename_project": "Rename Symbol Project-Wide", "type_hierarchy": "Type Hierarchy",
        ]
        let expectedRequired: [String: [String]] = [
            "call_hierarchy": ["function"], "code_summary": ["path"], "dependency_graph": [], "extract_code_symbols": ["path"],
            "import_graph": [], "protocol_conformance_list": ["protocol"], "search_regex": ["pattern"],
            "search_skills": ["query"], "search_symbol": ["symbol"], "search_text": ["pattern"],
            "semantic_query_engine": ["query"], "source_graph_builder": [],
            "symbol_move_file": ["symbol", "sourcePath", "destinationPath"], "symbol_reference_graph": ["symbol"],
            "symbol_rename_project": ["oldName", "newName"], "type_hierarchy": [],
        ]
        let expectedOutputs: [String: [String]] = [
            "call_hierarchy": ["callerCount", "calleeCount", "definitionCount", "function"],
            "code_summary": ["summary"], "dependency_graph": ["edge_count", "edges", "node_count", "nodes"],
            "extract_code_symbols": ["path", "symbolCount"], "import_graph": ["edgeCount", "fileCount", "module", "moduleCount"],
            "protocol_conformance_list": ["count", "protocol"], "search_regex": ["results"], "search_skills": [],
            "search_symbol": ["results"], "search_text": ["results"], "semantic_query_engine": ["matches"],
            "source_graph_builder": ["file_count", "imports", "node_count", "relationship_count", "relationships"],
            "symbol_move_file": ["destinationPath", "kind", "movedLines", "sourcePath", "symbol"],
            "symbol_reference_graph": [], "symbol_rename_project": ["changedFileCount", "filesChanged", "replacementCount"],
            "type_hierarchy": ["childCount", "type", "typeCount"],
        ]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name])
            if tool.name == "symbol_move_file" || tool.name == "symbol_rename_project" {
                #expect(!tool.annotations.readOnly && tool.annotations.idempotent && !tool.annotations.destructive && tool.writes,
                        "\(tool.name) must be a gated safe-mutation tool")
            } else {
                #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes, "\(tool.name) must be a read-only tool")
            }
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs[tool.name], "\(tool.name) output keys: \(outputKeys)")
        }
        // The host serves them once installed (the coordinator wires
        // `searchTools` into `installTools()`; filter-first so they are
        // not registered twice).
        let installed = Set(host.searchTools.map(\.name))
        host.server.tools = host.server.tools.filter { !installed.contains($0.name) } + host.searchTools
        let served = host.server.tools.map(\.name)
        for id in Self.searchIDs { #expect(served.contains(id), "\(id) is not installed on the server") }
    }

    @Test func searchTextFindsCaseInsensitiveMatches() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("search_text", [:])
        #expect(missing.isToolError && missing.resultText.contains("missing the required argument \"pattern\""))
        let found = try await host.server.callTool("search_text", ["pattern": .string("salutation")])
        #expect(!found.isToolError, "\(found.resultText)")
        let results = found.structured?["results"]?.string ?? ""
        #expect(results.hasPrefix("Sources/Greeter/Greeter.swift:\n4:     public var salutation: String\n6:     public init(salutation: String = \"Hello\") {\n7:         self.salutation = salutation\n12:         \"\\(salutation), \\(name)!\""))
        #expect(results.contains("Tests/GreeterTests/GreeterTests.swift:\n10:"))
        #expect(found.firstText == "Search results for 'salutation':")
        let upper = try await host.server.callTool("search_text", ["pattern": .string("SALUTATION")])
        #expect(upper.structured?["results"] == found.structured?["results"])
        let none = try await host.server.callTool("search_text", ["pattern": .string("zzzz-no-such-text")])
        #expect(!none.isToolError && none.structured?["results"]?.string == "")
    }

    @Test func searchRegexFindsPatternAndRejectsInvalidRegex() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let found = try await host.server.callTool("search_regex", ["pattern": .string("greeting\\(for")])
        #expect(!found.isToolError, "\(found.resultText)")
        let results = found.structured?["results"]?.string ?? ""
        #expect(results.contains("Sources/Greeter/Greeter.swift:11:     public func greeting(for name: String) -> String {"))
        #expect(results.contains("Sources/greet/main.swift:4:"))
        #expect(results.contains("Tests/GreeterTests/GreeterTests.swift:6:"))
        #expect(results.contains("Tests/GreeterTests/GreeterTests.swift:10:"))
        #expect(found.firstText == "Regex search completed for 'greeting\\(for'")
        let bad = try await host.server.callTool("search_regex", ["pattern": .string("[")])
        #expect(bad.isToolError && bad.resultText.contains("Regex search failed"))
    }

    @Test func searchSymbolFindsDeclarations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let greeter = try await host.server.callTool("search_symbol", ["symbol": .string("Greeter")])
        #expect(!greeter.isToolError, "\(greeter.resultText)")
        #expect(greeter.structured?["results"]?.string == "Sources/Greeter/Greeter.swift:2: public struct Greeter {")
        let greeting = try await host.server.callTool("search_symbol", ["symbol": .string("greeting")])
        #expect(greeting.structured?["results"]?.string == "Sources/Greeter/Greeter.swift:11:     public func greeting(for name: String) -> String {")
        #expect(greeting.firstText == "Symbol search completed for 'greeting'")
    }

    @Test func extractCodeSymbolsListsDeclarations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let read = try await host.server.callTool("extract_code_symbols", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(!read.isToolError, "\(read.resultText)")
        #expect(read.structured?["path"]?.string == "Sources/Greeter/Greeter.swift")
        #expect(read.structured?["symbolCount"]?.int == 2)
        #expect(read.resultText.contains("Extracted 2 declaration symbol(s) from `Sources/Greeter/Greeter.swift`:"))
        #expect(read.resultText.contains("  • L2: [struct] public struct Greeter"))
        #expect(read.resultText.contains("  • L11: [func] public func greeting(for name: String) -> String"))
        let missing = try await host.server.callTool("extract_code_symbols", ["path": .string("Nope.swift")])
        #expect(missing.isToolError && missing.resultText.contains("File not found at: Nope.swift"))
        let outside = try await host.server.callTool("extract_code_symbols", ["path": .string("../../etc/hosts")])
        #expect(outside.isToolError && outside.resultText.contains("Path is outside the workspace"))
    }

    @Test func codeSummaryForFileAndDirectory() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let file = try await host.server.callTool("code_summary", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(!file.isToolError, "\(file.resultText)")
        #expect(file.structured?["summary"]?.string == "File Sources/Greeter/Greeter.swift: 15 lines (12 non-empty), 3 comment lines")
        #expect(file.firstText == "Summary for Sources/Greeter/Greeter.swift")
        let dir = try await host.server.callTool("code_summary", ["path": .string(".")])
        #expect(dir.structured?["summary"]?.string == "Directory .: 6 files, 5 code files")
        let missing = try await host.server.callTool("code_summary", ["path": .string("Nope")])
        #expect(missing.isToolError && missing.resultText.contains("Path does not exist: Nope"))
    }

    @Test func dependencyGraphCountsImports() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let graph = try await host.server.callTool("dependency_graph")
        #expect(!graph.isToolError, "\(graph.resultText)")
        #expect(graph.structured?["node_count"]?.int == 9)
        #expect(graph.structured?["edge_count"]?.int == 4)
        #expect((graph.structured?["nodes"]?.string ?? "").contains("PackageDescription"))
        #expect((graph.structured?["edges"]?.string ?? "").contains("Sources/greet/main.swift -> Greeter"))
        #expect(graph.firstText == "Dependency graph generated for 5 files.")
    }

    @Test func importGraphByModuleAndOverall() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let byModule = try await host.server.callTool("import_graph", ["module": .string("Greeter")])
        #expect(!byModule.isToolError, "\(byModule.resultText)")
        #expect(byModule.structured?["module"]?.string == "Greeter")
        #expect(byModule.structured?["fileCount"]?.int == 1)
        #expect(byModule.resultText.contains("- Sources/greet/main.swift"))
        let overall = try await host.server.callTool("import_graph")
        #expect(overall.structured?["edgeCount"]?.int == 4)
        #expect(overall.structured?["moduleCount"]?.int == 4)
        #expect(overall.resultText.contains("Import edges (4 total, showing 4):"))
    }

    @Test func protocolConformanceListFindsView() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let view = try await host.server.callTool("protocol_conformance_list", ["protocol": .string("View")])
        #expect(!view.isToolError, "\(view.resultText)")
        #expect(view.structured?["protocol"]?.string == "View")
        #expect(view.structured?["count"]?.int == 1)
        #expect(view.resultText.contains("GreetingView — Previews/GreetingView.swift:4"))
        let none = try await host.server.callTool("protocol_conformance_list", ["protocol": .string("Sequence")])
        #expect(none.structured?["count"]?.int == 0)
        #expect(none.firstText == "No conformances to protocol 'Sequence' found.")
        let missing = try await host.server.callTool("protocol_conformance_list", [:])
        #expect(missing.isToolError && missing.resultText.contains("missing the required argument \"protocol\""))
    }

    @Test func typeHierarchyListsAndFocuses() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let all = try await host.server.callTool("type_hierarchy")
        #expect(!all.isToolError, "\(all.resultText)")
        #expect(all.structured?["typeCount"]?.int == 3)
        #expect(all.resultText.contains("- struct Greeter — Sources/Greeter/Greeter.swift:2"))
        #expect(all.resultText.contains("- struct GreetingView: View — Previews/GreetingView.swift:4"))
        #expect(all.resultText.contains("- class GreeterTests: XCTestCase — Tests/GreeterTests/GreeterTests.swift:4"))
        let focused = try await host.server.callTool("type_hierarchy", ["type": .string("GreetingView")])
        #expect(focused.structured?["type"]?.string == "GreetingView")
        #expect(focused.structured?["childCount"]?.int == 0)
        #expect(focused.resultText.contains("Type hierarchy for 'GreetingView' (struct) at Previews/GreetingView.swift:4:"))
        #expect(focused.resultText.contains("Inherits/conforms to:\n- View"))
        #expect(focused.resultText.contains("Subtypes (0):\n- (none)"))
        let missing = try await host.server.callTool("type_hierarchy", ["type": .string("Nope")])
        #expect(missing.isToolError && missing.resultText.contains("Type 'Nope' not found in workspace Swift sources."))
    }

    @Test func callHierarchyFindsDefinitionWithoutCallers() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let found = try await host.server.callTool("call_hierarchy", ["function": .string("greeting")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["function"]?.string == "greeting")
        #expect(found.structured?["definitionCount"]?.int == 1)
        #expect(found.structured?["callerCount"]?.int == 0)
        #expect(found.structured?["calleeCount"]?.int == 0)
        #expect(found.resultText.contains("Definitions (1):\n- Sources/Greeter/Greeter.swift:11"))
        #expect(found.resultText.contains("Callers (0):"))
        #expect(found.resultText.contains("Callees (0 distinct):"))
        let none = try await host.server.callTool("call_hierarchy", ["function": .string("nonexistent")])
        #expect(none.firstText == "No definition or callers found for function 'nonexistent'.")
        #expect(none.structured?["definitionCount"]?.int == 0 && none.structured?["callerCount"]?.int == 0)
        let missing = try await host.server.callTool("call_hierarchy", ["function": .string("  ")])
        #expect(missing.isToolError && missing.resultText.contains("missing the required argument \"function\""))
    }

    @Test func symbolReferenceGraphReportsUsages() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let graph = try await host.server.callTool("symbol_reference_graph", ["symbol": .string("salutation")])
        #expect(!graph.isToolError, "\(graph.resultText)")
        #expect(graph.resultText.contains("### Symbol Reference Graph for `salutation` (4 sites found):"))
        #expect(graph.resultText.contains("#### Usages & Call Sites:"))
        #expect(graph.resultText.contains("- `Sources/Greeter/Greeter.swift:4` → `public var salutation: String`"))
        #expect(graph.resultText.contains("- `Tests/GreeterTests/GreeterTests.swift:10` → `XCTAssertEqual(Greeter(salutation: \"Hi\").greeting(for: \"Bo\"), \"Hi, Bo!\")`"))
        let none = try await host.server.callTool("symbol_reference_graph", ["symbol": .string("zzzz")])
        #expect(none.firstText == "No references found for symbol 'zzzz' in workspace.")
        let capped = try await host.server.callTool("symbol_reference_graph", ["symbol": .string("salutation"), "maxResults": .int(2)])
        #expect(capped.resultText.contains("(2 sites found)"))
    }

    @Test func sourceGraphBuilderCountsFiles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let graph = try await host.server.callTool("source_graph_builder")
        #expect(!graph.isToolError, "\(graph.resultText)")
        #expect(graph.structured?["file_count"]?.int == 5)
        #expect(graph.structured?["imports"]?.string == "Greeter,PackageDescription,SwiftUI,XCTest")
        #expect((graph.structured?["node_count"]?.int ?? 0) > 5)
        #expect((graph.structured?["relationship_count"]?.int ?? 0) > 0)
        #expect(graph.firstText == "Built source graph for 5 Swift files.")
        let missing = try await host.server.callTool("source_graph_builder", ["path": .string("Nope")])
        #expect(missing.isToolError && missing.resultText.contains("Path does not exist:"))
    }

    @Test func semanticQueryExpandsViewShortcut() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let found = try await host.server.callTool("semantic_query_engine", ["query": .string("view")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.firstText == "Semantic query returned 7 matches.")
        let matches = found.structured?["matches"]?.string ?? ""
        #expect(matches.contains("Previews/GreetingView.swift::4::"))
        #expect(matches.contains("Previews/GreetingView.swift::6::"))
        let none = try await host.server.callTool("semantic_query_engine", ["query": .string("zzzz-no-such-word")])
        #expect(none.firstText == "Semantic query returned 0 matches.")
        #expect(none.structured?["matches"]?.string == "")
    }

    @Test func searchSkillsFindsWorkspaceSkill() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("search_skills", ["query": .string("greeting")])
        #expect(!none.isToolError, "\(none.resultText)")
        #expect(none.resultText.contains("No skills found matching query 'greeting'."))
        try writeFixture(sample, ".claude/skills/greeter-helper/SKILL.md", """
        ---
        name: Greeter Helper
        description: Helps write greetings in Swift.
        tags: [greeting, swift]
        ---
        # Greeter Helper

        Write a greeting with `Greeter().greeting(for:)`.
        """)
        let found = try await host.server.callTool("search_skills", ["query": .string("greeting")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.resultText.contains("### Discovered Skills Matching 'greeting' (1 results):"))
        #expect(found.resultText.contains("1. **Greeter Helper** (`greeter-helper`)"))
        #expect(found.resultText.contains("- **Source**: Claude (Claude Skills)"))
        #expect(found.resultText.contains("- **Description**: Helps write greetings in Swift."))
        #expect(found.resultText.contains("- **Tags**: greeting, swift"))
        #expect(found.resultText.contains("SKILL.md"))
        #expect(found.resultText.contains("inspect instructions using `file_read`"))
        let missing = try await host.server.callTool("search_skills", ["query": .string("   ")])
        #expect(missing.isToolError && missing.resultText.contains("missing the required argument \"query\""))
    }

    @Test func symbolRenameProjectRenamesWholeWord() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let renamed = try await host.server.callTool("symbol_rename_project",
                                                     ["oldName": .string("salutation"), "newName": .string("greetingWord")])
        #expect(!renamed.isToolError, "\(renamed.resultText)")
        #expect(renamed.structured?["replacementCount"]?.int == 5)
        #expect(renamed.structured?["changedFileCount"]?.int == 2)
        #expect(renamed.structured?["filesChanged"]?.string == "Sources/Greeter/Greeter.swift\nTests/GreeterTests/GreeterTests.swift")
        #expect(renamed.resultText.contains("Rename Symbol: replaced 5 whole-word occurrence(s) of 'salutation' with 'greetingWord' across 2 file(s):"))
        #expect(sample.read("Sources/Greeter/Greeter.swift").contains("greetingWord"))
        #expect(!sample.read("Sources/Greeter/Greeter.swift").contains("salutation"))
        #expect(sample.read("Tests/GreeterTests/GreeterTests.swift").contains("greetingWord"))

        let refusedSample = try TempSample()
        defer { refusedSample.remove() }
        let refused = try await opened(refusedSample, policy: .readOnly)
        let denied = try await refused.server.callTool("symbol_rename_project",
                                                       ["oldName": .string("salutation"), "newName": .string("greetingWord")])
        #expect(denied.isToolError)

        let invalid = try await host.server.callTool("symbol_rename_project",
                                                     ["oldName": .string("not valid"), "newName": .string("greetingWord")])
        #expect(invalid.isToolError && invalid.resultText.contains("Invalid oldName 'not valid'"))
        let identical = try await host.server.callTool("symbol_rename_project",
                                                       ["oldName": .string("salutation"), "newName": .string("salutation")])
        #expect(identical.isToolError && identical.resultText.contains("Refusing rename: oldName and newName are identical ('salutation')."))
        let noMatch = try await host.server.callTool("symbol_rename_project",
                                                     ["oldName": .string("zzzz"), "newName": .string("yyyy")])
        #expect(!noMatch.isToolError && noMatch.structured?["replacementCount"]?.int == 0)
        #expect(noMatch.resultText.contains("no whole-word occurrences of 'zzzz' found in 5 Swift file(s). Nothing changed."))
    }

    @Test func symbolMoveFileMovesDeclaration() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let moved = try await host.server.callTool("symbol_move_file",
                                                   ["symbol": .string("greeting"),
                                                    "sourcePath": .string("Sources/Greeter/Greeter.swift"),
                                                    "destinationPath": .string("Previews/GreetingView.swift")])
        #expect(!moved.isToolError, "\(moved.resultText)")
        #expect(moved.structured?["symbol"]?.string == "greeting")
        #expect(moved.structured?["kind"]?.string == "func")
        #expect(moved.structured?["movedLines"]?.int == 3)
        #expect(moved.firstText == "Moved symbol 'greeting' (func, 3 line(s)) from Sources/Greeter/Greeter.swift to Previews/GreetingView.swift.")
        #expect(!sample.read("Sources/Greeter/Greeter.swift").contains("func greeting"))
        #expect(sample.read("Previews/GreetingView.swift").contains("public func greeting(for name: String) -> String {"))

        let unknown = try await host.server.callTool("symbol_move_file",
                                                     ["symbol": .string("nope"),
                                                      "sourcePath": .string("Sources/Greeter/Greeter.swift"),
                                                      "destinationPath": .string("Previews/GreetingView.swift")])
        #expect(unknown.isToolError && unknown.resultText.contains("Symbol 'nope' declaration not found in Sources/Greeter/Greeter.swift."))
        let clash = try await host.server.callTool("symbol_move_file",
                                                   ["symbol": .string("name"),
                                                    "sourcePath": .string("Previews/GreetingView.swift"),
                                                    "destinationPath": .string("Sources/greet/main.swift")])
        #expect(clash.isToolError && clash.resultText.contains("Refusing move: destination already declares 'name'."))
        let same = try await host.server.callTool("symbol_move_file",
                                                  ["symbol": .string("greeting"),
                                                   "sourcePath": .string("Sources/Greeter/Greeter.swift"),
                                                   "destinationPath": .string("Sources/Greeter/Greeter.swift")])
        #expect(same.isToolError && same.resultText.contains("Refusing move: sourcePath and destinationPath must differ."))

        let refusedSample = try TempSample()
        defer { refusedSample.remove() }
        let refusedHost = try await opened(refusedSample, policy: .readOnly)
        let denied = try await refusedHost.server.callTool("symbol_move_file",
                                                           ["symbol": .string("greeting"),
                                                            "sourcePath": .string("Sources/Greeter/Greeter.swift"),
                                                            "destinationPath": .string("Previews/GreetingView.swift")])
        #expect(denied.isToolError)
    }
}
