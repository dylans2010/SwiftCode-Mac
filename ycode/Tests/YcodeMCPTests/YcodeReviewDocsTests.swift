import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

/// The ported Legacy docs / review / repo-tooling family (Wave 6, slice D),
/// each driven black-box through the server's real write-policy path
/// against a copy of `Samples/AgentSamples/Greeter`.
///
/// Behaviour source: Legacy `AssistApiDocsCoverageTool`,
/// `AssistApiEndpointAuditTool`, `AssistApiSurfaceExtractTool`,
/// `AssistReadmeGenerateTool`, `AssistReadmeLocateTool`,
/// `AssistRepoOverviewTool`, `AssistMarkdownLinkCheckTool`,
/// `AssistMarkdownTocGenerateTool`, `CodeReviewTool`,
/// `AssistAutomatedRepairEngine`, `AssistAutonomousReviewEngine`,
/// `AssistDocStringGeneratorTool`, `AssistCodeSnippetTool`,
/// `AssistIconGeneratorTool`, `AssistColorUsageAuditTool`,
/// `AssistColorSetBuilderTool`, `AssistStaleFilesReportTool`,
/// `AssistChangeImpactEstimateTool`, `AssistUndoTool`,
/// `AssistValidateChangesTool`, `AssistSessionExportTool`,
/// `AssistSessionProgressReportTool` and `AssistToolCapabilityLookupTool`
/// (Dylan's own code, ported under MIT).
///
/// Assertions are on the tool RESULT (message + on-disk state), never on
/// internals. Messages quoted verbatim are Legacy's. Message assertions
/// use `firstText`, never exact `resultText ==` (structured results emit
/// two text blocks).
///
/// `code_review` and `safe_undo` are the deliberate exceptions: Legacy
/// implements them through an LLM review stage and a workspace snapshot
/// store respectively, neither of which Ycode's MCP host has, so the
/// tests assert they fail cleanly and change nothing (Wave 2
/// `code_refactor` precedent).
///
/// Fixture facts used below (verified from the sample): the workspace has
/// 5 Swift files (`Package.swift`, `Sources/Greeter/Greeter.swift`,
/// `Sources/greet/main.swift`, `Previews/GreetingView.swift`,
/// `Tests/GreeterTests/GreeterTests.swift`) and one `.xcstrings` file.
/// `Greeter.swift` has 4 public declarations, all documented
/// (`struct Greeter` line 2, `var salutation` line 4, `init` line 6,
/// `func greeting` line 11); `api_surface_extract` counts 3 of them
/// (its declaration pattern has no `init` kind). `Greeter` is referenced
/// by `main.swift` (`import Greeter`, `Greeter().greeting(for:)`) and by
/// `GreeterTests.swift` (`Greeter()`, `Greeter(salutation:)`), so its
/// change impact is MEDIUM with 2 referencing files.
@MainActor
@Suite(.serialized) struct YcodeReviewDocsTests {
    /// The 23 slice-D tool IDs, in install order, verified live from each
    /// Legacy tool's `id` (plus `CodeReviewTool` in `CodeReview.swift`,
    /// whose registering class was confirmed by reading the file).
    static let reviewDocsIDs = ["api_docs_coverage", "api_endpoint_audit", "api_surface_extract", "automated_repair_engine",
                                "autonomous_review_engine", "change_impact_estimate", "code_review", "code_snippet_manager",
                                "color_usage_audit", "colorset_builder", "docstring_generator", "icon_generator_tool",
                                "markdown_link_check", "markdown_toc_generate", "readme_generate", "readme_locate",
                                "repo_overview", "safe_undo", "safe_validate_changes", "session_export",
                                "session_progress_report", "stale_files_report", "tool_capability_lookup"]

    /// The 7 slice-D tools that write files.
    static let writingIDs = Set(["automated_repair_engine", "colorset_builder", "icon_generator_tool", "markdown_toc_generate",
                                 "readme_generate", "safe_undo", "session_export"])

    /// Opens a copy of Greeter and installs the ported review/docs tools
    /// on the server (same shape as Wave 2's `opened`; the coordinator
    /// wires `reviewDocsTools` into `installTools()`).
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.reviewDocsTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.reviewDocsTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    final class Reviews: @unchecked Sendable {
        var changes: [MCPChange] = []
        var accept = false
    }

    /// Writes a fixture file directly (not through a tool under test).
    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func exists(_ sample: TempSample, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: sample.path(rel))
    }

    /// Counts the non-hidden files under the sample, skipping the same
    /// top-level build/dependency directories `repo_overview` skips.
    func visibleFileCount(_ sample: TempSample) -> Int {
        let skipped: Set<String> = [".git", ".build", "build", "DerivedData", ".swiftpm", "Pods", "Carthage", "node_modules", ".venv"]
        var count = 0
        let root = URL(fileURLWithPath: sample.url.path)
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles]) else { return 0 }
        while let url = enumerator.nextObject() as? URL {
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            if skipped.contains(rel.split(separator: "/").first.map(String.init) ?? "") { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir { count += 1 }
        }
        return count
    }

    @Test func toolsAreRegisteredWithLegacyIDsTitlesAndRisk() async throws {
        let host = YcodeMCPHost()
        let tools = host.reviewDocsTools
        #expect(tools.map(\.name) == Self.reviewDocsIDs)
        let expectedTitles: [String: String] = [
            "api_docs_coverage": "API Docs Coverage", "api_endpoint_audit": "API Endpoint Audit",
            "api_surface_extract": "API Surface", "automated_repair_engine": "Automated Repair Engine",
            "autonomous_review_engine": "Autonomous Review Engine", "change_impact_estimate": "Change Impact Estimate",
            "code_review": "Code Review Validation", "code_snippet_manager": "Code Snippet & Architecture Template Manager",
            "color_usage_audit": "Color Usage Audit", "colorset_builder": "Color Set Builder",
            "docstring_generator": "DocC Documentation Generator", "icon_generator_tool": "App Icon Generator & Validator",
            "markdown_link_check": "Markdown Link Check", "markdown_toc_generate": "Markdown TOC Generate",
            "readme_generate": "README Generate", "readme_locate": "Locate README",
            "repo_overview": "Repository Overview", "safe_undo": "Undo Last Action",
            "safe_validate_changes": "Validate Changes", "session_export": "Export Session",
            "session_progress_report": "Session Progress Report", "stale_files_report": "Stale Files Report",
            "tool_capability_lookup": "Tool Capability Lookup",
        ]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name], "title for \(tool.name)")
            #expect(tool.writes == Self.writingIDs.contains(tool.name), "writes flag for \(tool.name)")
            #expect(tool.annotations.readOnly != tool.writes, "readOnly/writes agree for \(tool.name)")
        }
        // Verbatim Legacy descriptions, spot-checked.
        let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        #expect(byName["api_docs_coverage"]?.description == "Measures the share of public/open Swift declarations that carry documentation comments.")
        #expect(byName["code_review"]?.description == "Validates the completed implementation using an independent AI reviewer stage before finishing the task.")
        #expect(byName["safe_undo"]?.description == "Reverts the last modification made by the agent.")
        #expect(byName["session_export"]?.description == "Writes a markdown export with session metadata (title, timestamp, session ID, workspace, notes). Does not read conversation history. Refuses to overwrite unless overwrite is true.")
        #expect(byName["safe_undo"]?.annotations.destructive == true)
        // Every tool takes the workspace parameter.
        for tool in tools {
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "workspace param for \(tool.name)")
        }
    }

    @Test func readOnlyRefusesWriteTools() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let refused = try await host.server.callTool("readme_generate", [:])
        #expect(refused.isToolError)
        #expect(refused.firstText.contains("read-only"))
        let undone = try await host.server.callTool("safe_undo", [:])
        #expect(undone.isToolError)
        #expect(undone.firstText.contains("read-only"))
        #expect(!exists(sample, "README.generated.md"))
    }

    @Test func apiDocsCoverageCountsDocumentedDeclarations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("api_docs_coverage", [:])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["total"] == 4)
        #expect(r.structured?["documented"] == 4)
        #expect(r.structured?["coverage"] == "100.0")
        #expect(r.firstText.contains("API docs coverage: 100.0% (4 of 4 public declarations documented)"))
        // An undocumented public declaration is listed, capped by limit.
        try writeFixture(sample, "Sources/Greeter/Undocumented.swift", "public struct Undocumented {\n    public var value: Int\n}\n")
        let capped = try await host.server.callTool("api_docs_coverage", ["limit": .int(1)])
        #expect(!capped.isToolError, "\(capped.resultText)")
        #expect(capped.structured?["total"] == 6)
        #expect(capped.structured?["documented"] == 4)
        #expect(capped.firstText.contains("Undocumented (showing 1):"))
        #expect(capped.firstText.contains("Undocumented.swift:1:"))
    }

    @Test func apiEndpointAuditGroupsByHostAndSkipsExamples() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let clean = try await host.server.callTool("api_endpoint_audit", [:])
        #expect(!clean.isToolError, "\(clean.resultText)")
        #expect(clean.firstText.contains("No hardcoded http(s) endpoints found in Swift sources."))
        #expect(clean.structured?["count"] == 0)
        try writeFixture(sample, "Sources/Greeter/Endpoints.swift",
                         """
                         import Foundation
                         let api = "https://api.acme.test/v1/items"
                         let other = "https://api.acme.test/v1/other"
                         // "https://ignored.acme.test/x"
                         let docs = "https://developer.apple.com/documentation"
                         """)
        let r = try await host.server.callTool("api_endpoint_audit", [:])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["hostCount"] == 1)
        #expect(r.structured?["siteCount"] == 2)
        #expect(r.firstText.contains("- api.acme.test: 2"))
        #expect(!r.firstText.contains("ignored.acme.test"))
        #expect(!r.firstText.contains("developer.apple.com"))
    }

    @Test func apiSurfaceExtractListsPublicDeclarations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("api_surface_extract", [:])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["scannedFiles"] == 5)
        #expect(r.structured?["declarationCount"] == 3)
        #expect(r.firstText.contains("found 3 public/open declaration(s) across 1 file(s)."))
        #expect(r.firstText.contains("Sources/Greeter/Greeter.swift:2 public struct Greeter"))
        let single = try await host.server.callTool("api_surface_extract", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(!single.isToolError, "\(single.resultText)")
        #expect(single.structured?["scannedFiles"] == 1)
        #expect(single.structured?["declarationCount"] == 3)
        let outside = try await host.server.callTool("api_surface_extract", ["path": .string("../outside")])
        #expect(outside.isToolError)
        #expect(outside.firstText.contains("Invalid path: path must stay inside the workspace and must not contain '..'."))
    }

    @Test func readmeLocateFindsReadmeOrFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("readme_locate", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("No README file found in the workspace."))
        try writeFixture(sample, "README.md", "# Greeter Docs\n\nA small sample package.\n")
        let found = try await host.server.callTool("readme_locate", [:])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["count"] == 1)
        #expect(found.firstText.contains("- README.md: # Greeter Docs"))
    }

    @Test func readmeGenerateWritesSkeletonAndRefusesOverwrite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("readme_generate", [:])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("README skeleton written to README.generated.md."))
        #expect(r.structured?["path"] == "README.generated.md")
        let text = sample.read("README.generated.md")
        #expect(text.contains("# Greeter"))
        #expect(text.contains("- Build systems: SwiftPM"))
        #expect(text.contains("- Swift source files: 5"))
        let again = try await host.server.callTool("readme_generate", [:])
        #expect(again.isToolError)
        #expect(again.firstText.contains("File already exists at README.generated.md. Pass overwrite: true to replace it."))
        let over = try await host.server.callTool("readme_generate", ["overwrite": .bool(true)])
        #expect(!over.isToolError, "\(over.resultText)")
    }

    @Test func repoOverviewSummarizesWorkspace() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("repo_overview", [:])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["fileCount"] == visibleFileCount(sample))
        #expect(r.firstText.contains("Repository overview for Greeter:"))
        #expect(r.firstText.contains("- README: not found"))
        #expect(r.firstText.contains("- License: not found"))
        #expect(r.firstText.contains("  - .swift: 5 files"))
        #expect(r.firstText.contains("- Largest files:"))
    }

    @Test func markdownLinkCheckReportsBrokenLinks() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Docs/guide.md",
                         """
                         # Guide
                         See [Greeter](../Sources/Greeter/Greeter.swift) and [Missing](Nope.md).
                         Jump to [top](#guide) or visit [Apple](https://www.apple.com).
                         """)
        let r = try await host.server.callTool("markdown_link_check", [:])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["checked"] == 2)
        #expect(r.structured?["broken"] == 1)
        #expect(r.firstText.contains("Broken internal links (1 of 2 checked):"))
        #expect(r.firstText.contains("Docs/guide.md: [Nope.md]"))
        // A single unreadable file is skipped, not an error (Legacy).
        let missing = try await host.server.callTool("markdown_link_check", ["path": .string("Docs/Nope.md")])
        #expect(!missing.isToolError, "\(missing.resultText)")
        #expect(missing.firstText.contains("All 0 internal links resolve."))
    }

    @Test func markdownTocGenerateInsertsAndUpdates() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Docs/notes.md", "# Notes\n\n## Getting Started\n\n### Details\n\n#### Too Deep\n\nBody text.\n")
        let r = try await host.server.callTool("markdown_toc_generate", ["path": .string("Docs/notes.md")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["entryCount"] == 3)
        #expect(r.firstText.contains("Table of contents (3 entries) written to Docs/notes.md."))
        var text = sample.read("Docs/notes.md")
        #expect(text.contains("<!-- TOC -->\n- [Notes](#notes)\n  - [Getting Started](#getting-started)\n    - [Details](#details)\n<!-- /TOC -->"))
        #expect(!text.contains("Too Deep"))
        // A second run updates the block in place instead of duplicating it.
        let again = try await host.server.callTool("markdown_toc_generate", ["path": .string("Docs/notes.md")])
        #expect(!again.isToolError, "\(again.resultText)")
        text = sample.read("Docs/notes.md")
        #expect(text.components(separatedBy: "<!-- TOC -->").count == 2)
        // No headings is a failure, not an empty TOC.
        try writeFixture(sample, "Docs/plain.md", "Just prose, no headings.\n")
        let empty = try await host.server.callTool("markdown_toc_generate", ["path": .string("Docs/plain.md")])
        #expect(empty.isToolError)
        #expect(empty.firstText.contains("No headings found in Docs/plain.md."))
    }

    @Test func codeReviewFailsHonestlyWithoutLLM() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let before = sample.read("Sources/Greeter/Greeter.swift")
        let r = try await host.server.callTool("code_review", [:])
        #expect(r.isToolError)
        #expect(r.firstText.contains("no LLM provider"))
        #expect(r.firstText.contains("task_ready"))
        #expect(sample.read("Sources/Greeter/Greeter.swift") == before)
    }

    @Test func automatedRepairAnnotatesDiagnosticLines() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let missing = try await host.server.callTool("automated_repair_engine", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("missing the required argument \"errors\""))
        let empty = try await host.server.callTool("automated_repair_engine", ["errors": .string("")])
        #expect(empty.isToolError)
        #expect(empty.firstText.contains("Missing compiler errors payload"))
        let r = try await host.server.callTool("automated_repair_engine", [
            "errors": .string("Sources/Greeter/Greeter.swift:2: error: something broke\nSources/Greeter/Greeter.swift:99: error: out of range\nREADME.md:1: error: not a Swift diagnostic\n"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["fix_count"] == 1)
        #expect(r.firstText.contains("Applied 1 automated repair annotations."))
        let lines = sample.read("Sources/Greeter/Greeter.swift").components(separatedBy: .newlines)
        #expect(lines[1] == "// AssistAutoRepair: review required")
        #expect(lines[2] == "public struct Greeter {")
        // Lines without '.swift:' are ignored entirely.
        let none = try await host.server.callTool("automated_repair_engine", ["errors": .string("README.md:1: error: nope\n")])
        #expect(!none.isToolError, "\(none.resultText)")
        #expect(none.structured?["fix_count"] == 0)
    }

    @Test func autonomousReviewFindsInefficientPatterns() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let clean = try await host.server.callTool("autonomous_review_engine", [:])
        #expect(!clean.isToolError, "\(clean.resultText)")
        #expect(clean.structured?["finding_count"] == 0)
        #expect(clean.firstText.contains("Autonomous review complete."))
        try writeFixture(sample, "Sources/Greeter/ReviewMe.swift",
                         """
                         import Foundation
                         public func reviewMe(_ maybe: String?) {
                             let x = maybe!
                             DispatchQueue.main.async { print(x) }
                             Task { print("hi") }
                             for i in 0..<3 { print(i) }
                             for i in 0..<3 { print(i) }
                             for i in 0..<3 { print(i) }
                             for i in 0..<3 { print(i) }
                             for i in 0..<3 { print(i) }
                             for i in 0..<3 { print(i) }
                             for i in 0..<3 { print(i) }
                         }
                         """)
        let r = try await host.server.callTool("autonomous_review_engine", [:])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["finding_count"] == 3)
        #expect(r.firstText.contains("Autonomous review complete."))
    }

    @Test func docstringGeneratorBuildsDocCComment() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("docstring_generator", [
            "declaration": .string("func fetchUser(id: String) throws -> User"),
            "summary": .string("Fetches a user."),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("/// Fetches a user."))
        #expect(r.firstText.contains("/// - Parameter id: The String value supplied for processing."))
        #expect(r.firstText.contains("/// - Throws: An error if processing or I/O fails during execution."))
        #expect(r.firstText.contains("/// - Returns: A `User` instance representing the computed outcome."))
        let missing = try await host.server.callTool("docstring_generator", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("missing the required argument \"declaration\""))
    }

    @Test func codeSnippetManagerReturnsTemplatesAndRejectsUnknown() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let vm = try await host.server.callTool("code_snippet_manager", ["templateId": .string("observable_viewmodel"), "targetName": .string("Login")])
        #expect(!vm.isToolError, "\(vm.resultText)")
        #expect(vm.firstText.contains("Swift 6 @Observable ViewModel Template:"))
        #expect(vm.firstText.contains("public final class LoginViewModel"))
        let stream = try await host.server.callTool("code_snippet_manager", ["templateId": .string("ASYNC_STREAM"), "targetName": .string("Chat")])
        #expect(!stream.isToolError, "\(stream.resultText)")
        #expect(stream.firstText.contains("public func makeChatStream() -> AsyncStream<String>"))
        let unknown = try await host.server.callTool("code_snippet_manager", ["templateId": .string("nope")])
        #expect(unknown.isToolError)
        #expect(unknown.firstText.contains("Unknown templateId 'nope'. Available: observable_viewmodel, async_stream, actor_service, swiftui_glass_card"))
        // Legacy's schema lists keychain_helper, but its switch has no
        // such case: it fails like any unknown template.
        let keychain = try await host.server.callTool("code_snippet_manager", ["templateId": .string("keychain_helper")])
        #expect(keychain.isToolError)
        #expect(keychain.firstText.contains("Unknown templateId 'keychain_helper'."))
    }

    @Test func iconGeneratorScaffoldsAndValidatesAppIcon() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let missing = try await host.server.callTool("icon_generator_tool", ["catalogPath": .string("Assets.xcassets"), "action": .string("validate")])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("Contents.json not found or invalid"))
        let scaffold = try await host.server.callTool("icon_generator_tool", ["catalogPath": .string("Assets.xcassets"), "action": .string("scaffold")])
        #expect(!scaffold.isToolError, "\(scaffold.resultText)")
        #expect(scaffold.firstText.contains("Successfully created universal AppIcon.appiconset at:"))
        let contents = sample.read("Assets.xcassets/AppIcon.appiconset/Contents.json")
        #expect(contents.contains("\"size\" : \"1024x1024\""))
        let audit = try await host.server.callTool("icon_generator_tool", ["catalogPath": .string("Assets.xcassets"), "action": .string("validate")])
        #expect(!audit.isToolError, "\(audit.resultText)")
        #expect(audit.firstText.contains("- Total slots configured: 11"))
        #expect(audit.firstText.contains("- Rendered assets present: 0"))
        #expect(audit.firstText.contains("- Empty/unassigned slots: 11"))
    }

    @Test func colorUsageAuditFindsHardcodedColors() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let clean = try await host.server.callTool("color_usage_audit", [:])
        #expect(!clean.isToolError, "\(clean.resultText)")
        #expect(clean.structured?["count"] == 0)
        #expect(clean.firstText.contains("No hardcoded colors found"))
        try writeFixture(sample, "Sources/Greeter/Colors.swift",
                         """
                         import SwiftUI
                         let a = Color(red: 1, green: 0, blue: 0)
                         let b = "#FF0000"
                         // let c = Color(red: 0, green: 0, blue: 0)
                         """)
        let r = try await host.server.callTool("color_usage_audit", [:])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["count"] == 2)
        #expect(r.firstText.contains("[Color(red:...)]"))
        #expect(r.firstText.contains("[hex literal]"))
    }

    @Test func colorsetBuilderWritesAdaptiveColorset() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("colorset_builder", [
            "catalogPath": .string("Assets.xcassets"), "colorName": .string("BrandPrimary"),
            "lightHex": .string("#007AFF"), "darkHex": .string("#0A84FF"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Successfully built adaptive ColorSet `BrandPrimary`"))
        #expect(r.firstText.contains("- Light: #007AFF"))
        #expect(r.firstText.contains("- Dark: #0A84FF"))
        let contents = sample.read("Assets.xcassets/BrandPrimary.colorset/Contents.json")
        #expect(contents.contains("\"red\" : \"0.000\""))
        #expect(contents.contains("\"green\" : \"0.478\""))
        #expect(contents.contains("\"blue\" : \"1.000\""))
        // An unparseable hex falls back to Legacy's #007AFF components.
        let fallback = try await host.server.callTool("colorset_builder", [
            "catalogPath": .string("Assets.xcassets"), "colorName": .string("Fallback"),
            "lightHex": .string("xyz"),
        ])
        #expect(!fallback.isToolError, "\(fallback.resultText)")
        #expect(sample.read("Assets.xcassets/Fallback.colorset/Contents.json").contains("\"green\" : \"0.478\""))
        // A path-like color name is refused.
        let bad = try await host.server.callTool("colorset_builder", [
            "catalogPath": .string("Assets.xcassets"), "colorName": .string("a/b"), "lightHex": .string("#FFFFFF"),
        ])
        #expect(bad.isToolError)
        #expect(bad.firstText.contains("Invalid colorName"))
    }

    @Test func staleFilesReportFindsOldSources() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // The sample copy may carry the checkout's old mtimes: normalise
        // every source file to now so only the fixture below is stale.
        let sourceExts: Set<String> = ["swift", "m", "mm", "h", "c", "cpp", "hpp", "ts", "js", "py", "rs"]
        let fm = FileManager.default
        let enumerator = try #require(fm.enumerator(at: sample.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
        while let url = enumerator.nextObject() as? URL {
            if sourceExts.contains(url.pathExtension.lowercased()) {
                try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            }
        }
        let fresh = try await host.server.callTool("stale_files_report", [:])
        #expect(!fresh.isToolError, "\(fresh.resultText)")
        #expect(fresh.firstText.contains("No source files older than 180 days."))
        try writeFixture(sample, "Sources/Greeter/Old.swift", "public struct Old {}\n")
        let oldDate = Date(timeIntervalSince1970: 1_577_880_000) // 2020-01-01T12:00:00Z
        try FileManager.default.setAttributes([.modificationDate: oldDate],
                                              ofItemAtPath: sample.path("Sources/Greeter/Old.swift"))
        let r = try await host.server.callTool("stale_files_report", [:])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["count"] == 1)
        #expect(r.firstText.contains("Sources/Greeter/Old.swift"))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(r.firstText.contains("modified \(formatter.string(from: oldDate))"))
    }

    @Test func changeImpactEstimateRanksReferencingFiles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("change_impact_estimate", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["symbol"] == "Greeter")
        #expect(r.structured?["referencingFileCount"] == 2)
        #expect(r.structured?["blastRadius"] == "MEDIUM")
        #expect(r.firstText.contains("- Blast radius: MEDIUM — referenced by 2 file(s)"))
        #expect(r.firstText.contains("- Sources/greet/main.swift"))
        #expect(r.firstText.contains("- Tests/GreeterTests/GreeterTests.swift"))
        let missing = try await host.server.callTool("change_impact_estimate", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("missing the required argument \"path\""))
        let outside = try await host.server.callTool("change_impact_estimate", ["path": .string("../Greeter.swift")])
        #expect(outside.isToolError)
        #expect(outside.firstText.contains("Refusing to access path outside the workspace: ../Greeter.swift"))
    }

    @Test func safeUndoFailsHonestlyWithoutSnapshots() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let before = sample.read("Sources/Greeter/Greeter.swift")
        let r = try await host.server.callTool("safe_undo", [:])
        #expect(r.isToolError)
        #expect(r.firstText.contains("snapshot"))
        #expect(r.firstText.contains("Nothing was changed."))
        #expect(sample.read("Sources/Greeter/Greeter.swift") == before)
    }

    @Test func safeValidateChangesFlagsMarkersAndMissingNewline() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let clean = try await host.server.callTool("safe_validate_changes", [:])
        #expect(!clean.isToolError, "\(clean.resultText)")
        #expect(clean.structured?["issue_count"] == 0)
        #expect(clean.firstText.contains("Changes validated successfully"))
        try writeFixture(sample, "Sources/Greeter/Broken.swift", "let a = 1\n<<<<<<< HEAD\nlet b = 2")
        let r = try await host.server.callTool("safe_validate_changes", ["path": .string("Sources/Greeter/Broken.swift")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["issue_count"] == 2)
        #expect(r.firstText.contains("Validation completed with 2 issue(s)"))
    }

    @Test func sessionExportWritesMetadataAndRefusesOverwrite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("session_export", ["title": .string("Greeter Session"), "notes": .string("First export.")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Session export written to .assist_session_export.md (session "))
        let text = sample.read(".assist_session_export.md")
        #expect(text.contains("# Greeter Session"))
        #expect(text.contains("- Session ID: "))
        #expect(text.contains("- Workspace: \(sample.url.path)"))
        #expect(text.contains("First export."))
        #expect(text.contains("Tool definitions live in AssistToolRegistry."))
        #expect(r.structured?["output_relative"] == ".assist_session_export.md")
        #expect(!(r.structured?["session_id"]?.string ?? "").isEmpty)
        // A second export refuses to overwrite unless overwrite is "true".
        let again = try await host.server.callTool("session_export", [:])
        #expect(again.isToolError)
        #expect(again.firstText.contains("Refusing to overwrite existing file at '.assist_session_export.md'."))
        let over = try await host.server.callTool("session_export", ["overwrite": .string("true")])
        #expect(!over.isToolError, "\(over.resultText)")
        // The session id is stable per workspace.
        #expect(over.structured?["session_id"] == r.structured?["session_id"])
        // An escaping output path is refused.
        let outside = try await host.server.callTool("session_export", ["outputPath": .string("../export.md"), "overwrite": .string("true")])
        #expect(outside.isToolError)
        #expect(outside.firstText.contains("Invalid outputPath: '../export.md'"))
    }

    @Test func sessionProgressReportReadsAgentNotesTime() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("session_progress_report", [:])
        #expect(!none.isToolError, "\(none.resultText)")
        #expect(none.structured?["phaseCount"] == 0)
        #expect(none.firstText.contains("No engineering phases are registered for this session."))
        #expect(none.firstText.contains("Agent notes: never saved this session."))
        try writeFixture(sample, "agent_notes.md", "# Plan\n\nDo the thing.\n")
        let savedDate = Date(timeIntervalSince1970: 1_774_008_000) // 2026-03-20T12:00:00Z
        try FileManager.default.setAttributes([.modificationDate: savedDate],
                                              ofItemAtPath: sample.path("agent_notes.md"))
        let saved = try await host.server.callTool("session_progress_report", [:])
        #expect(!saved.isToolError, "\(saved.resultText)")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(saved.firstText.contains("Agent notes last saved: \(formatter.string(from: savedDate))"))
    }

    @Test func toolCapabilityLookupReadsLiveRegistry() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("tool_capability_lookup", ["toolId": .string("repo_overview")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["toolId"] == "repo_overview")
        #expect(r.structured?["riskLevel"] == "safeRead")
        #expect(r.structured?["required"] == "")
        #expect(r.firstText.contains("Tool: repo_overview — Repository Overview"))
        #expect(r.firstText.contains("Risk level: safeRead"))
        #expect(r.firstText.contains("Read-only: true, Mutating: false"))
        #expect(r.firstText.contains("Parameters: topLanguages, workspace"))
        let write = try await host.server.callTool("tool_capability_lookup", ["toolId": .string("readme_generate")])
        #expect(!write.isToolError, "\(write.resultText)")
        #expect(write.structured?["riskLevel"] == "safeMutation")
        #expect(write.firstText.contains("Read-only: false, Mutating: true"))
        // An alias resolves to its target, as in Legacy's getTool.
        let aliased = try await host.server.callTool("tool_capability_lookup", ["toolId": .string("search_dir")])
        #expect(!aliased.isToolError, "\(aliased.resultText)")
        #expect(aliased.structured?["toolId"] == "search_text")
        let unknown = try await host.server.callTool("tool_capability_lookup", ["toolId": .string("nope")])
        #expect(unknown.isToolError)
        #expect(unknown.firstText.contains("No registered tool with id 'nope'."))
        let missing = try await host.server.callTool("tool_capability_lookup", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("missing the required argument \"toolId\""))
    }

    @Test func reviewGateRejectsAndAcceptsReadmeGenerate() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let reviews = Reviews()
        let host = try await opened(sample, policy: .review { c in reviews.changes.append(c); return reviews.accept })
        let rejected = try await host.server.callTool("readme_generate", [:])
        #expect(rejected.isToolError)
        #expect(rejected.firstText == MCPServer.rejectedMessage)
        #expect(!exists(sample, "README.generated.md"))
        let change = try #require(reviews.changes.first)
        #expect(change.tool == "readme_generate" && change.relativePath == "README.generated.md")
        #expect(change.original == nil)
        reviews.accept = true
        let created = try await host.server.callTool("readme_generate", [:])
        #expect(!created.isToolError, "\(created.resultText)")
        #expect(exists(sample, "README.generated.md"))
    }
}
