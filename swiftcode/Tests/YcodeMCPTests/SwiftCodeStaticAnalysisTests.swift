import Foundation
import Testing
import YcodeAssistant
import YcodeIDECore
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeStaticAnalysisTests {
    static let staticAnalysisIDs = ["code_lint", "swift_format_lint", "dead_code_scan", "dead_code_eliminator",
                                    "duplicate_code_scan", "unused_imports_detector", "import_cleanup", "force_unwrap_scan",
                                    "todo_scan", "todo_fixme_scanner", "comment_density_report", "code_comment_extract",
                                    "complexity_analysis", "function_size_report", "code_metrics_analyzer", "string_literal_audit",
                                    "deprecation_usage_scan", "swift_ast_inspector", "swift_concurrency_analyzer", "concurrency_audit",
                                    "entry_points_discover", "swift_migration_advisor"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.staticAnalysisTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.staticAnalysisTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.staticAnalysisTools
        #expect(tools.map(\.name) == Self.staticAnalysisIDs)
        let expectedTitles: [String: String] = [
            "code_lint": "Lint Code", "swift_format_lint": "Swift Format Linter", "dead_code_scan": "Dead Code Scan",
            "dead_code_eliminator": "Dead Code Eliminator", "duplicate_code_scan": "Duplicate Code Scan",
            "unused_imports_detector": "Unused Imports Detector", "import_cleanup": "Import Cleanup",
            "force_unwrap_scan": "Force Unwrap Scan", "todo_scan": "TODO Scan", "todo_fixme_scanner": "TODO & FIXME Scanner",
            "comment_density_report": "Comment Density Report", "code_comment_extract": "Code Comment Extract",
            "complexity_analysis": "Complexity Analysis", "function_size_report": "Function Size Report",
            "code_metrics_analyzer": "Code Metrics Analyzer", "string_literal_audit": "String Literal Audit",
            "deprecation_usage_scan": "Deprecation Usage Scan", "swift_ast_inspector": "Swift AST Inspector",
            "swift_concurrency_analyzer": "Swift Concurrency Analyzer", "concurrency_audit": "Concurrency Audit",
            "entry_points_discover": "Discover Entry Points", "swift_migration_advisor": "Swift 6 Migration Advisor",
        ]
        let expectedRequired: [String: [String]] = [
            "code_lint": [], "swift_format_lint": ["path"], "dead_code_scan": [], "dead_code_eliminator": ["filePath"],
            "duplicate_code_scan": [], "unused_imports_detector": ["path"], "import_cleanup": ["path"],
            "force_unwrap_scan": [], "todo_scan": [], "todo_fixme_scanner": [], "comment_density_report": [],
            "code_comment_extract": ["path"], "complexity_analysis": ["path"], "function_size_report": [],
            "code_metrics_analyzer": ["path"], "string_literal_audit": [], "deprecation_usage_scan": [],
            "swift_ast_inspector": ["path"], "swift_concurrency_analyzer": ["path"], "concurrency_audit": [],
            "entry_points_discover": [], "swift_migration_advisor": ["path"],
        ]
        let expectedOutputs: [String: [String]] = [
            "code_lint": ["issues"], "swift_format_lint": [], "dead_code_scan": ["candidateCount", "candidates", "declarationCount", "scannedFiles"],
            "dead_code_eliminator": [], "duplicate_code_scan": ["duplicateGroups", "groups", "scannedFiles"],
            "unused_imports_detector": [], "import_cleanup": ["changedFileCount", "filesChanged", "removed", "removedImports"],
            "force_unwrap_scan": ["count"], "todo_scan": ["findings", "fixme", "hack", "scannedFiles", "todo", "totalMarkers", "xxx"],
            "todo_fixme_scanner": [], "comment_density_report": ["fileCount"], "code_comment_extract": ["count"],
            "complexity_analysis": ["rating", "score"], "function_size_report": ["count"], "code_metrics_analyzer": [],
            "string_literal_audit": ["count"], "deprecation_usage_scan": ["declarationCount", "usageCount"],
            "swift_ast_inspector": [], "swift_concurrency_analyzer": [], "concurrency_audit": ["findingCount", "findings", "scannedFiles"],
            "entry_points_discover": ["count"], "swift_migration_advisor": [],
        ]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name])
            if tool.name == "import_cleanup" {
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
        let installed = Set(host.staticAnalysisTools.map(\.name))
        host.server.tools = host.server.tools.filter { !installed.contains($0.name) } + host.staticAnalysisTools
        let served = host.server.tools.map(\.name)
        for id in Self.staticAnalysisIDs { #expect(served.contains(id), "\(id) is not installed on the server") }
    }

    @Test func codeLintFlagsLongLinesAndMarkers() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let long = String(repeating: "x", count: 121)
        try writeFixture(sample, "Analysis/Lint.swift", "// TODO: fix this\nstruct Lint { }\n\(long)\n")
        let found = try await host.server.callTool("code_lint", ["path": .string("Analysis/Lint.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["issues"]?.string?.contains("Line 1 contains a marker: // TODO: fix this") == true)
        #expect(found.structured?["issues"]?.string?.contains("Line 3 is too long (121 chars)") == true)
        #expect(found.firstText == "Basic linting found 2 issues in Analysis/Lint.swift")
        try writeFixture(sample, "Analysis/Clean.swift", "struct Clean { }\n")
        let clean = try await host.server.callTool("code_lint", ["path": .string("Analysis/Clean.swift")])
        #expect(!clean.isToolError && clean.firstText == "No basic linting issues found in Analysis/Clean.swift")
        let missing = try await host.server.callTool("code_lint", ["path": .string("Analysis/Nope.swift")])
        #expect(missing.isToolError && missing.firstText.contains("Failed to lint Analysis/Nope.swift"))
    }

    @Test func swiftFormatLintFlagsStyleViolations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Format.swift", "struct Format {\n\tvar x = 1\n    var y = 2; \n}\n")
        let found = try await host.server.callTool("swift_format_lint", ["path": .string("Analysis/Format.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.firstText.contains("Line 2: Hard tab indentation used instead of spaces."))
        #expect(found.firstText.contains("Line 3: Trailing whitespace detected."))
        #expect(found.firstText.contains("Line 3: Redundant trailing semicolon."))
        let missingArg = try await host.server.callTool("swift_format_lint", [:])
        #expect(missingArg.isToolError && missingArg.firstText.contains("missing the required argument \"path\""))
        let missingFile = try await host.server.callTool("swift_format_lint", ["path": .string("Analysis/Nope.swift")])
        #expect(missingFile.isToolError && missingFile.firstText == "File not found at path: Analysis/Nope.swift")
    }

    @Test func deadCodeScanFlagsUnreferencedDeclarations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Dead.swift", "struct Dead {\n    func used() -> Int { 1 }\n    func unusedHelper() -> Int { 2 }\n    func callUsed() -> Int { used() }\n}\n")
        let found = try await host.server.callTool("dead_code_scan", ["path": .string("Analysis")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["scannedFiles"]?.int == 1)
        #expect(found.structured?["declarationCount"]?.int == 4)
        #expect(found.structured?["candidateCount"]?.int == 3)
        #expect(found.structured?["candidates"]?.string?.contains("Analysis/Dead.swift:3 func unusedHelper") == true)
        #expect(found.structured?["candidates"]?.string?.contains("Analysis/Dead.swift:4 func callUsed") == true)
        #expect(found.firstText.contains("No dead-code candidates found.") == false)
        let badPath = try await host.server.callTool("dead_code_scan", ["path": .string("../outside")])
        #expect(badPath.isToolError && badPath.firstText == "Invalid path: path must stay inside the workspace and must not contain '..'.")
        let empty = try await host.server.callTool("dead_code_scan", ["path": .string("Analysis/Nope.swift")])
        #expect(!empty.isToolError && empty.structured?["scannedFiles"]?.int == 0)
    }

    @Test func deadCodeEliminatorReportsUnusedPrivateFuncs() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Elim.swift", "struct Elim {\n    private func hiddenHelper() { }\n    private func shownHelper() { }\n    func callIt() { shownHelper() }\n}\n")
        let found = try await host.server.callTool("dead_code_eliminator", ["filePath": .string("Analysis/Elim.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.firstText.contains("Unused private function 'hiddenHelper()'"))
        #expect(found.firstText.contains("shownHelper") == false)
        let missingArg = try await host.server.callTool("dead_code_eliminator", [:])
        #expect(missingArg.isToolError && missingArg.firstText.contains("missing the required argument \"filePath\""))
        let missingFile = try await host.server.callTool("dead_code_eliminator", ["filePath": .string("Analysis/Nope.swift")])
        #expect(missingFile.isToolError && missingFile.firstText == "File does not exist: Analysis/Nope.swift")
    }

    @Test func duplicateCodeScanFindsRepeatedBlock() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let block = ["    let a = 1", "    let b = 2", "    let c = 3", "    let d = 4", "    let e = 5", "    print(a + b + c + d + e)"]
        let content = "func first() {\n" + block.joined(separator: "\n") + "\n}\n\nfunc second() {\n" + block.joined(separator: "\n") + "\n}\n"
        try writeFixture(sample, "Analysis/Dup.swift", content)
        let found = try await host.server.callTool("duplicate_code_scan", ["path": .string("Analysis")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["scannedFiles"]?.int == 1)
        #expect(found.structured?["duplicateGroups"]?.int == 1)
        #expect(found.structured?["groups"]?.string?.contains("Duplicate block ×2:") == true)
        #expect(found.structured?["groups"]?.string?.contains("Analysis/Dup.swift:2") == true)
        let tiny = try await host.server.callTool("duplicate_code_scan", ["path": .string("Analysis"), "minLines": .string("3")])
        #expect(!tiny.isToolError && (tiny.structured?["duplicateGroups"]?.int ?? 0) >= 1)
    }

    @Test func unusedImportsDetectorFlagsUnknownModule() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Imports.swift", "import Combine\nimport Foundation\n\nstruct Imports {\n    var body: String { \"hi\" }\n}\n")
        let found = try await host.server.callTool("unused_imports_detector", ["path": .string("Analysis/Imports.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.firstText.contains("`import Combine`"))
        #expect(found.firstText.contains("Foundation") == false)
        try writeFixture(sample, "Analysis/OnlyFoundation.swift", "import Foundation\n\nstruct OnlyFoundation {\n    var x = 1\n}\n")
        let clean = try await host.server.callTool("unused_imports_detector", ["path": .string("Analysis/OnlyFoundation.swift")])
        #expect(!clean.isToolError && clean.firstText.contains("Import analysis clean"))
    }

    @Test func importCleanupRemovesUnusedImportThroughApproval() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let readOnlyHost = try await opened(sample)
        try writeFixture(sample, "Analysis/Cleanup.swift", "import FooKit\nimport Foundation\n\nstruct Cleanup {\n    var x = 1\n}\n")
        let refused = try await readOnlyHost.server.callTool("import_cleanup", ["path": .string("Analysis/Cleanup.swift")])
        #expect(refused.isToolError && refused.firstText.contains("read-only"))
        #expect(sample.read("Analysis/Cleanup.swift").contains("import FooKit"))
        let host = try await opened(sample, policy: .allow)
        let cleaned = try await host.server.callTool("import_cleanup", ["path": .string("Analysis/Cleanup.swift")])
        #expect(!cleaned.isToolError, "\(cleaned.resultText)")
        #expect(cleaned.structured?["removedImports"]?.int == 1)
        #expect(cleaned.structured?["changedFileCount"]?.int == 1)
        #expect(cleaned.structured?["filesChanged"]?.string == "Analysis/Cleanup.swift")
        #expect(sample.read("Analysis/Cleanup.swift").contains("import FooKit") == false)
        #expect(sample.read("Analysis/Cleanup.swift").contains("import Foundation"))
        let again = try await host.server.callTool("import_cleanup", ["path": .string("Analysis/Cleanup.swift")])
        #expect(!again.isToolError && again.structured?["removedImports"]?.int == 0)
        #expect(again.firstText.contains("Nothing changed."))
    }

    @Test func forceUnwrapScanFindsForceUnwraps() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Force.swift", "struct Force {\n    func get(_ x: Int?) -> Int {\n        x!\n    }\n}\n")
        let found = try await host.server.callTool("force_unwrap_scan", [:])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect((found.structured?["count"]?.int ?? 0) >= 1)
        #expect(found.firstText.contains("Analysis/Force.swift:3 [force unwrap (!)]"))
        let limited = try await host.server.callTool("force_unwrap_scan", ["limit": .int(1)])
        #expect(!limited.isToolError && limited.structured?["count"]?.int == 1)
    }

    @Test func todoScanCountsMarkersPerTag() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Todo.swift", "// TODO: fix this later\n// FIXME: broken thing\n// TODO: another one\n// HACK: workaround\n// XXX: check this\nstruct Todo { }\n")
        let found = try await host.server.callTool("todo_scan", ["path": .string("Analysis")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["scannedFiles"]?.int == 1)
        #expect(found.structured?["totalMarkers"]?.int == 5)
        #expect(found.structured?["todo"]?.int == 2)
        #expect(found.structured?["fixme"]?.int == 1)
        #expect(found.structured?["xxx"]?.int == 1)
        #expect(found.structured?["hack"]?.int == 1)
        #expect(found.structured?["findings"]?.string?.contains("Analysis/Todo.swift:1 TODO: fix this later") == true)
    }

    @Test func todoFixmeScannerGroupsByTagAndFilters() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Tags.swift", "// TODO: do this\n// FIXME: fix that\n// MARK: - Section\n// BUG: bad bug\nstruct Tags { }\n")
        let all = try await host.server.callTool("todo_fixme_scanner", [:])
        #expect(!all.isToolError, "\(all.resultText)")
        #expect(all.firstText.contains("#### TODO (1):"))
        #expect(all.firstText.contains("#### FIXME (1):"))
        #expect(all.firstText.contains("#### MARK (1):"))
        #expect(all.firstText.contains("#### BUG (1):"))
        let filtered = try await host.server.callTool("todo_fixme_scanner", ["tag": .string("TODO")])
        #expect(!filtered.isToolError && filtered.firstText.contains("#### TODO (1):"))
        #expect(filtered.firstText.contains("FIXME") == false)
        #expect(filtered.firstText.contains("MARK") == false)
    }

    @Test func commentDensityReportOrdersLowestFirst() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Bare.swift", "struct Bare {\n    var x = 1\n    func f() -> Int { x }\n}\n")
        try writeFixture(sample, "Analysis/Docced.swift", "// comment one\n// comment two\nstruct Docced {\n    var x = 1\n}\n")
        let found = try await host.server.callTool("comment_density_report", [:])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect((found.structured?["fileCount"]?.int ?? 0) >= 2)
        #expect(found.firstText.contains("0.0% — Analysis/Bare.swift (0 comment / 4 code lines)"))
        let bareIndex = found.firstText.range(of: "Analysis/Bare.swift")?.lowerBound
        let doccedIndex = found.firstText.range(of: "Analysis/Docced.swift")?.lowerBound
        #expect(bareIndex != nil && doccedIndex != nil && bareIndex! < doccedIndex!)
    }

    @Test func codeCommentExtractFindsDocComments() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Docs.swift", "/// Greets the user.\n/// Returns a friendly string.\nfunc greet() -> String { \"hi\" }\n\n/// Undocumented helper below.\nstruct Docs {\n    var x = 1\n}\n")
        let found = try await host.server.callTool("code_comment_extract", ["path": .string("Analysis/Docs.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["count"]?.int == 2)
        #expect(found.firstText.contains("Greets the user."))
        #expect(found.firstText.contains("func greet()"))
        let filtered = try await host.server.callTool("code_comment_extract", ["path": .string("Analysis/Docs.swift"), "symbol": .string("greet")])
        #expect(!filtered.isToolError && filtered.structured?["count"]?.int == 1)
        let none = try await host.server.callTool("code_comment_extract", ["path": .string("Analysis/Docs.swift"), "symbol": .string("zzz-no-such-symbol")])
        #expect(!none.isToolError && none.structured?["count"]?.int == 0)
        #expect(none.firstText.contains("No documentation comments found"))
        let missing = try await host.server.callTool("code_comment_extract", ["path": .string("Analysis/Nope.swift")])
        #expect(missing.isToolError && missing.firstText == "Cannot read file at: Analysis/Nope.swift")
    }

    @Test func complexityAnalysisScoresControlFlow() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Complex.swift", "func check(_ x: Int) -> Int {\n    if x > 0 {\n        return x\n    }\n    if x < 0 {\n        return -x\n    }\n    for i in 0..<3 {\n        print(i)\n    }\n    return 0\n}\n")
        let found = try await host.server.callTool("complexity_analysis", ["path": .string("Analysis/Complex.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["score"]?.int == 4)
        #expect(found.structured?["rating"]?.string == "Low")
        #expect(found.firstText == "Complexity analysis for Analysis/Complex.swift: Low (Cyclomatic approximation: 4)")
        let missing = try await host.server.callTool("complexity_analysis", ["path": .string("Analysis/Nope.swift")])
        #expect(missing.isToolError && missing.firstText.contains("Failed to analyze complexity for Analysis/Nope.swift"))
    }

    @Test func functionSizeReportFindsLongFunctions() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let body = (1...9).map { "    let v\($0) = \($0)" }.joined(separator: "\n")
        try writeFixture(sample, "Analysis/Long.swift", "func longOne() {\n\(body)\n    print(v1 + v2)\n}\n")
        let found = try await host.server.callTool("function_size_report", ["threshold": .int(10)])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect((found.structured?["count"]?.int ?? 0) >= 1)
        #expect(found.firstText.contains("longOne — Analysis/Long.swift:1 (12 lines)"))
        let none = try await host.server.callTool("function_size_report", ["threshold": .int(500)])
        #expect(!none.isToolError && none.structured?["count"]?.int == 0)
        #expect(none.firstText == "No functions with 500+ lines found.")
    }

    @Test func codeMetricsAnalyzerCountsLinesTypesAndBranches() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let lines = ["import Foundation", "", "// A comment line", "struct Metrics {", "    var count = 0", "",
                     "    func increment() {", "        if count > 0 {", "            count += 1", "        }", "    }", "",
                     "    func reset() {", "        count = 0", "    }", "}"]
        try writeFixture(sample, "Analysis/Metrics.swift", lines.joined(separator: "\n") + "\n")
        let found = try await host.server.callTool("code_metrics_analyzer", ["path": .string("Analysis/Metrics.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.firstText.contains("Code Metrics for 'Analysis/Metrics.swift' (1 Swift files):"))
        #expect(found.firstText.contains("- Total Lines: 17"))
        #expect(found.firstText.contains("- Code Lines: 12"))
        #expect(found.firstText.contains("- Blank Lines: 4"))
        #expect(found.firstText.contains("- Comment Lines: 1 (8.3% comment ratio)"))
        #expect(found.firstText.contains("- Declared Types (struct/class/enum/actor): 1"))
        #expect(found.firstText.contains("- Functions: 2"))
        #expect(found.firstText.contains("- Decision Branches (if/guard/for/while/case): 1"))
        #expect(found.firstText.contains("- Avg Cyclomatic Complexity per Function: ~1.5"))
        try writeFixture(sample, "Analysis/notes.txt", "hello\n")
        let wrongType = try await host.server.callTool("code_metrics_analyzer", ["path": .string("Analysis/notes.txt")])
        #expect(wrongType.isToolError && wrongType.firstText == "Target is not a Swift source file: Analysis/notes.txt")
        let missing = try await host.server.callTool("code_metrics_analyzer", ["path": .string("Analysis/Nope.swift")])
        #expect(missing.isToolError && missing.firstText == "File or directory not found at: Analysis/Nope.swift")
    }

    @Test func stringLiteralAuditFlagsUnlocalizedUIStrings() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Strings.swift", "import SwiftUI\n\nstruct Strings: View {\n    var body: some View {\n        Text(\"Hello world\")\n        Text(NSLocalizedString(\"Localized\", comment: \"\"))\n    }\n}\n")
        let found = try await host.server.callTool("string_literal_audit", [:])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect((found.structured?["count"]?.int ?? 0) >= 1)
        #expect(found.firstText.contains("Analysis/Strings.swift:5: \"Hello world\""))
        #expect(found.firstText.contains("Localized") == false)
    }

    @Test func deprecationUsageScanFindsDeprecatedSymbolAndUses() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Deprecated.swift", "struct Deprecated {\n    @available(*, deprecated, message: \"Use newThing instead\")\n    func oldThing() { }\n\n    func useIt() {\n        oldThing()\n    }\n}\n")
        let found = try await host.server.callTool("deprecation_usage_scan", [:])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["declarationCount"]?.int == 1)
        #expect(found.structured?["usageCount"]?.int == 2)
        #expect(found.firstText.contains("oldThing — Analysis/Deprecated.swift:2"))
        #expect(found.firstText.contains("Analysis/Deprecated.swift:6: uses deprecated 'oldThing'"))
    }

    @Test func swiftASTInspectorListsTypeDeclarations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/AST.swift", "import Foundation\n\nstruct Foo: Equatable {\n    var x = 1\n}\n\nclass Bar: NSObject {\n    func baz() { }\n}\n")
        let found = try await host.server.callTool("swift_ast_inspector", ["path": .string("Analysis/AST.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.firstText.contains("- [struct] Foo : Equatable"))
        #expect(found.firstText.contains("- [class] Bar : NSObject"))
        let filtered = try await host.server.callTool("swift_ast_inspector", ["path": .string("Analysis/AST.swift"), "symbol": .string("Foo")])
        #expect(!filtered.isToolError && filtered.firstText.contains("[struct] Foo"))
        #expect(filtered.firstText.contains("Bar") == false)
        let missing = try await host.server.callTool("swift_ast_inspector", ["path": .string("Analysis/Nope.swift")])
        #expect(missing.isToolError && missing.firstText == "File not found at path: Analysis/Nope.swift")
    }

    @Test func swiftConcurrencyAnalyzerFlagsMutableGlobals() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Conc.swift", "struct Conc {\n    static var shared = 1\n    func useIt() {\n        DispatchQueue.main.sync { }\n    }\n}\n")
        let found = try await host.server.callTool("swift_concurrency_analyzer", ["path": .string("Analysis/Conc.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.firstText.contains("Mutable shared state `static var shared = 1`"))
        #expect(found.firstText.contains("`DispatchQueue.main.sync` call detected"))
        try writeFixture(sample, "Analysis/CleanConc.swift", "struct CleanConc {\n    let x = 1\n}\n")
        let clean = try await host.server.callTool("swift_concurrency_analyzer", ["path": .string("Analysis/CleanConc.swift")])
        #expect(!clean.isToolError && clean.firstText.contains("Clean concurrency scan!"))
        let missing = try await host.server.callTool("swift_concurrency_analyzer", ["path": .string("Analysis/Nope.swift")])
        #expect(missing.isToolError && missing.firstText == "Path not found: Analysis/Nope.swift")
    }

    @Test func concurrencyAuditFlagsMainSyncAndUnisolatedSwiftUI() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Audit.swift", "import SwiftUI\n\nstruct AuditView: View {\n    var body: some View {\n        Text(\"hi\")\n    }\n}\n")
        try writeFixture(sample, "Analysis/Audit2.swift", "func run() {\n    DispatchQueue.main.sync { }\n}\n")
        let found = try await host.server.callTool("concurrency_audit", ["path": .string("Analysis")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["scannedFiles"]?.int == 2)
        #expect(found.structured?["findingCount"]?.int == 2)
        #expect(found.structured?["findings"]?.string?.contains("SwiftUI type without @MainActor in file") == true)
        #expect(found.structured?["findings"]?.string?.contains("DispatchQueue.main.sync can deadlock when called from the main thread") == true)
        let badPath = try await host.server.callTool("concurrency_audit", ["path": .string("../outside")])
        #expect(badPath.isToolError && badPath.firstText == "Invalid path: path must stay inside the workspace and must not contain '..'.")
    }

    @Test func entryPointsDiscoverFindsMainAndAppDelegate() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/App.swift", "@main\nstruct MyApp: App {\n    var body: some Scene { WindowGroup { Text(\"hi\") } }\n}\n")
        let found = try await host.server.callTool("entry_points_discover", [:])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect((found.structured?["count"]?.int ?? 0) >= 2)
        #expect(found.firstText.contains("Analysis/App.swift:1: @main struct MyApp: App {"))
        #expect(found.firstText.contains("Sources/greet/main.swift: main.swift"))
    }

    @Test func swiftMigrationAdvisorFlagsLegacyPatterns() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Analysis/Migrate.swift", "import SwiftUI\n\nclass Store: ObservableObject {\n    static var shared = Store()\n    @Published var value = 0\n}\n")
        let found = try await host.server.callTool("swift_migration_advisor", ["path": .string("Analysis/Migrate.swift")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.firstText.contains("[Swift 6] Mutable static variable"))
        #expect(found.firstText.contains("[Swift 6 / Observation] Uses legacy 'ObservableObject'"))
        #expect(found.firstText.contains("[Swift 6 / Observation] Legacy '@Published'"))
        let missing = try await host.server.callTool("swift_migration_advisor", ["path": .string("Analysis/Nope.swift")])
        #expect(missing.isToolError && missing.firstText == "Path does not exist: Analysis/Nope.swift")
    }
}
