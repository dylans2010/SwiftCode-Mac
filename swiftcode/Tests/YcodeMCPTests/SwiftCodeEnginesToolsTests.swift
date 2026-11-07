import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeEnginesToolsTests {
    static let engineIDs = ["code_mutation_engine", "dependency_resolution_engine", "external_resource_gateway",
                            "patch_application_engine", "fetch_documentation", "reverse_analyze"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.engineTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.engineTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func bareHost() -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        let ported = Set(host.engineTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.engineTools
        return host
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.engineTools
        #expect(tools.map(\.name) == Self.engineIDs)
        let expectedTitles: [String: String] = [
            "code_mutation_engine": "Controlled Mutation Engine",
            "dependency_resolution_engine": "Dependency Resolution Engine",
            "external_resource_gateway": "External Resource Gateway",
            "patch_application_engine": "Patch Application Engine",
            "fetch_documentation": "Fetch Apple Documentation",
            "reverse_analyze": "Reverse Analyze",
        ]
        let expectedRequired: [String: [String]] = [
            "code_mutation_engine": ["path", "replacement"],
            "dependency_resolution_engine": ["packageURL"],
            "external_resource_gateway": ["url"],
            "patch_application_engine": ["path", "original", "updated"],
            "fetch_documentation": [],
            "reverse_analyze": ["targetPath"],
        ]
        let readOnlyIDs: Set<String> = ["fetch_documentation", "reverse_analyze"]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name] ?? "", "\(tool.name) title: \(tool.title)")
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            if readOnlyIDs.contains(tool.name) {
                #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes,
                        "\(tool.name) must be a read-only tool")
            } else {
                #expect(!tool.annotations.readOnly && tool.writes, "\(tool.name) must be a gated write/execution tool")
            }
        }
        #expect(tools.first { $0.name == "fetch_documentation" }?.annotations.openWorld == true,
                "fetch_documentation reads the outside world")
        #expect(tools.first { $0.name == "external_resource_gateway" }?.annotations.openWorld == true,
                "external_resource_gateway is an external side effect")
    }

    @Test func codeMutationEngineReplacesSymbolBody() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Sources/Greeter/Mutate.swift",
                         "func greet() -> String {\n    return \"hello\"\n}\n")
        let r = try await host.server.callTool("code_mutation_engine", [
            "path": .string("Sources/Greeter/Mutate.swift"),
            "symbol": .string("greet"),
            "replacement": .string("greet() -> String {\n    return \"bye\"\n}"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Applied minimal mutation to"))
        #expect(r.structured?["bytes_before"]?.int == 46)
        #expect(r.structured?["bytes_after"]?.int == 44)
        #expect(sample.read("Sources/Greeter/Mutate.swift").contains("return \"bye\""))
        #expect(!sample.read("Sources/Greeter/Mutate.swift").contains("return \"hello\""))
    }

    @Test func codeMutationEngineReplacesTargetEverywhere() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Sources/Greeter/Target.txt", "hello hello hello\n")
        let r = try await host.server.callTool("code_mutation_engine", [
            "path": .string("Sources/Greeter/Target.txt"),
            "target": .string("hello"),
            "replacement": .string("bye"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(sample.read("Sources/Greeter/Target.txt") == "bye bye bye\n")
    }

    @Test func codeMutationEngineRejectsUnknownSymbol() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Sources/Greeter/Mutate.swift", "func greet() -> String {\n    return \"hello\"\n}\n")
        let r = try await host.server.callTool("code_mutation_engine", [
            "path": .string("Sources/Greeter/Mutate.swift"),
            "symbol": .string("farewell"),
            "replacement": .string("x"),
        ])
        #expect(r.isToolError && r.resultText.contains("Unable to locate symbol body for: farewell"))
        #expect(sample.read("Sources/Greeter/Mutate.swift").contains("return \"hello\""))
    }

    @Test func codeMutationEngineRejectsNoChange() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Sources/Greeter/Target.txt", "hello\n")
        let r = try await host.server.callTool("code_mutation_engine", [
            "path": .string("Sources/Greeter/Target.txt"),
            "target": .string("hello"),
            "replacement": .string("hello"),
        ])
        #expect(r.isToolError && r.resultText.contains("No mutation produced"))
        #expect(sample.read("Sources/Greeter/Target.txt") == "hello\n")
    }

    @Test func codeMutationEngineRejectsEscapingPath() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("code_mutation_engine", [
            "path": .string("../outside.swift"),
            "target": .string("x"),
            "replacement": .string("y"),
        ])
        #expect(r.isToolError && r.resultText.contains("Path not allowed"))
        #expect(!FileManager.default.fileExists(atPath: sample.root.appendingPathComponent("outside.swift").path))
    }

    @Test func codeMutationEngineRequiresSymbolOrTarget() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Sources/Greeter/Target.txt", "hello\n")
        let r = try await host.server.callTool("code_mutation_engine", [
            "path": .string("Sources/Greeter/Target.txt"),
            "replacement": .string("bye"),
        ])
        #expect(r.isToolError && r.resultText.contains("Provide either symbol or target"))
        #expect(sample.read("Sources/Greeter/Target.txt") == "hello\n")
    }

    @Test func patchApplicationEngineAppliesPatch() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Sources/Greeter/Patch.txt", "line one\nline two\nline three\n")
        let r = try await host.server.callTool("patch_application_engine", [
            "path": .string("Sources/Greeter/Patch.txt"),
            "original": .string("line two"),
            "updated": .string("line TWO"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Patch applied to"))
        let diff = r.structured?["diff"]?.string ?? ""
        #expect(diff.contains("--- a/Sources/Greeter/Patch.txt"))
        #expect(diff.contains("-line two"))
        #expect(diff.contains("+line TWO"))
        #expect(sample.read("Sources/Greeter/Patch.txt") == "line one\nline TWO\nline three\n")
    }

    @Test func patchApplicationEngineRejectsMissingBlock() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Sources/Greeter/Patch.txt", "line one\nline two\n")
        let r = try await host.server.callTool("patch_application_engine", [
            "path": .string("Sources/Greeter/Patch.txt"),
            "original": .string("line missing"),
            "updated": .string("line TWO"),
        ])
        #expect(r.isToolError && r.resultText.contains("Patch integrity check failed: original block not found"))
        #expect(sample.read("Sources/Greeter/Patch.txt") == "line one\nline two\n")
    }

    @Test func patchApplicationEngineReplacesEveryOccurrence() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Sources/Greeter/Patch.txt", "a\nb\na\n")
        let r = try await host.server.callTool("patch_application_engine", [
            "path": .string("Sources/Greeter/Patch.txt"),
            "original": .string("a"),
            "updated": .string("c"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(sample.read("Sources/Greeter/Patch.txt") == "c\nb\nc\n")
    }

    @Test func patchUnifiedDiffIsLegacyNaiveDiff() {
        let diff = EnginesPatch.unifiedDiff(old: "a\nb\nc", new: "a\nB\nc", file: "f.swift")
        #expect(diff == "--- a/f.swift\n+++ b/f.swift\n-b\n+B")
    }

    @Test func dependencyResolutionEngineFailsWithoutProjectOrRuntime() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("dependency_resolution_engine",
                                               ["packageURL": .string("https://example.com/foo.git")])
        #expect(r.isToolError)
        #if os(macOS)
        #expect(r.resultText.contains("No Xcode project"))
        #else
        #expect(r.resultText.contains("Dependency resolution requires macOS runtime"))
        #endif
    }

    @Test func dependencyResolutionEngineRequiresPackageURL() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("dependency_resolution_engine", [:])
        #expect(r.isToolError
                && (r.resultText.contains("missing the required argument") || r.resultText.contains("Missing packageURL")),
                "\(r.resultText)")
    }

    @Test func externalResourceGatewayRejectsHttp() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("external_resource_gateway",
                                               ["url": .string("http://example.com/api.json")])
        #expect(r.isToolError && r.resultText.contains("Only HTTPS URLs with a host are allowed"))
    }

    @Test func externalResourceGatewayRejectsFileScheme() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("external_resource_gateway",
                                               ["url": .string("file:///etc/passwd")])
        #expect(r.isToolError && r.resultText.contains("Only HTTPS URLs with a host are allowed"))
    }

    @Test func externalResourceGatewayRequiresURL() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("external_resource_gateway", [:])
        #expect(r.isToolError
                && (r.resultText.contains("missing the required argument") || r.resultText.contains("Missing or invalid url")),
                "\(r.resultText)")
    }

    @Test func fetchDocumentationRequiresQueryOrURL() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("fetch_documentation", [:])
        #expect(r.isToolError && r.resultText.contains("Provide at least one of 'query' or 'url'."))
    }

    @Test func fetchDocumentationRejectsBadLanguage() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("fetch_documentation",
                                               ["query": .string("View"), "language": .string("rust")])
        #expect(r.isToolError && r.resultText.contains("Unsupported language 'rust'"))
    }

    @Test func fetchDocumentationRejectsNonAppleURL() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("fetch_documentation",
                                               ["url": .string("https://example.com/documentation/swiftui/view")])
        #expect(r.isToolError && r.resultText.contains("Rejected documentation URL"))
    }

    @Test func fetchDocumentationNeedsNoWorkspace() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("fetch_documentation",
                                               ["query": .string("View"), "language": .string("rust")])
        #expect(r.isToolError && r.resultText.contains("Unsupported language 'rust'"))
    }

    @Test func fetchDocumentationResolvesCandidates() throws {
        let withFramework = try EnginesDocs.resolveCandidates(query: "View", urlString: "", framework: "SwiftUI")
        #expect(withFramework.map(\.docPath) == ["documentation/swiftui/view", "documentation/swiftui"])
        let frameworkOnly = try EnginesDocs.resolveCandidates(query: "SwiftUI", urlString: "", framework: "SwiftUI")
        #expect(frameworkOnly.map(\.docPath) == ["documentation/swiftui"])
        let dotted = try EnginesDocs.resolveCandidates(query: "SwiftUI.View", urlString: "", framework: nil)
        #expect(dotted.map(\.docPath) == ["documentation/swiftui/view", "documentation/swiftui"])
        let fromURL = try EnginesDocs.resolveCandidates(query: "", urlString: "https://developer.apple.com/de/documentation/swiftui/view", framework: nil)
        #expect(fromURL.map(\.docPath) == ["documentation/swiftui/view"])
        #expect(throws: EnginesHTTPError.self) {
            try EnginesDocs.resolveCandidates(query: "View", urlString: "", framework: nil)
        }
        #expect(throws: EnginesHTTPError.self) {
            try EnginesDocs.resolveCandidates(query: "", urlString: "https://example.com/documentation/swiftui/view", framework: nil)
        }
    }

    @Test func fetchDocumentationParsesDocCJSON() throws {
        let json = """
        {
          "metadata": {
            "navigatorTitle": [{"type": "text", "text": "View"}],
            "platforms": [{"name": "iOS", "introducedAt": "13.0"}, {"name": "macOS", "introducedAt": "10.15"}]
          },
          "abstract": [{"type": "text", "text": "A SwiftUI view."}],
          "primaryContentSections": [
            {"kind": "declarations", "declarations": [{"languages": ["swift"], "tokens": [{"text": "protocol View"}], "platforms": ["iOS", "macOS"]}]},
            {"kind": "content", "content": [
              {"type": "paragraph", "inlineContent": [{"type": "text", "text": "Discussion text."}]},
              {"type": "codeListing", "syntax": "swift", "code": ["Text(hi)"]}
            ]}
          ],
          "references": {"doc://x": {"title": "Text", "url": "/documentation/swiftui/text"}},
          "seeAlsoSections": [{"identifiers": ["doc://x"]}]
        }
        """
        let page = EnginesDocs.parseDocCJSON(
            data: Data(json.utf8),
            canonicalURL: URL(string: "https://developer.apple.com/documentation/swiftui/view")!,
            finalJSONURL: URL(string: "https://developer.apple.com/tutorials/data/documentation/swiftui/view.json")!,
            language: "swift", includeExamples: true)
        let page = try #require(page)
        #expect(page.title == "View")
        #expect(page.abstract == "A SwiftUI view.")
        #expect(page.declarations == ["protocol View"])
        #expect(page.availability == ["iOS 13.0+", "macOS 10.15+"])
        #expect(page.discussion == "Discussion text.")
        #expect(page.examples == ["```swift\nText(hi)\n```"])
        #expect(page.relatedLinks.count == 1)
        #expect(page.relatedLinks.first?.url == "https://developer.apple.com/documentation/swiftui/text")
        #expect(page.retrievalMethod == "docc-json")
        #expect(page.canonicalURL.absoluteString == "https://developer.apple.com/documentation/swiftui/view")
        #expect(EnginesDocs.parseDocCJSON(data: Data("{}".utf8),
                                          canonicalURL: URL(string: "https://developer.apple.com/documentation/x")!,
                                          finalJSONURL: URL(string: "https://developer.apple.com/documentation/x")!,
                                          language: "swift", includeExamples: true) == nil)
    }

    @Test func fetchDocumentationParsesHTML() {
        let html = "<html><head><title>View | Apple Developer Documentation</title><meta name=\"description\" content=\"A SwiftUI view.\"></head><body><p>Hello world.</p><script>var x = 1;</script></body></html>"
        #expect(EnginesDocs.htmlTitle(html) == "View")
        #expect(EnginesDocs.htmlMetaDescription(html) == "A SwiftUI view.")
        let body = EnginesDocs.htmlBodyText(html)
        #expect(body.contains("Hello world."))
        #expect(!body.contains("var x"))
    }

    @Test func fetchDocumentationRendersResults() {
        let page = EnginesDocs.Page(
            title: "View", canonicalURL: URL(string: "https://developer.apple.com/documentation/swiftui/view")!,
            retrievalMethod: "docc-json", abstract: "A SwiftUI view.", declarations: ["protocol View"],
            availability: ["iOS 13.0+", "macOS 10.15+"], discussion: "Discussion text.",
            examples: ["```swift\nText(hi)\n```"],
            relatedLinks: [(title: "Text", url: "https://developer.apple.com/documentation/swiftui/text")])
        let rendered = EnginesDocs.render(pages: [page], platform: "iOS", query: "View")
        #expect(rendered.contains("# Apple Developer Documentation — \"View\""))
        #expect(rendered.contains("## 1. View"))
        #expect(rendered.contains("Canonical URL: https://developer.apple.com/documentation/swiftui/view"))
        #expect(rendered.contains("Retrieved via: Apple DocC structured data"))
        #expect(rendered.contains("```swift\nprotocol View\n```"))
        #expect(rendered.contains("- iOS 13.0+"))
        #expect(!rendered.contains("macOS 10.15+"), "the platform filter keeps only the matching availability line")
        #expect(rendered.contains("Text: https://developer.apple.com/documentation/swiftui/text"))
    }

    @Test func reverseAnalyzeRejectsUnknownOperation() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "artifact.bin", "fake binary")
        let r = try await host.server.callTool("reverse_analyze", [
            "targetPath": .string(sample.path("artifact.bin")),
            "operation": .string("bogus"),
        ])
        #expect(r.isToolError && r.resultText.contains("Unsupported Reverse operation 'bogus'"))
    }

    @Test func reverseAnalyzeRefusesDRMTask() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "artifact.bin", "fake binary")
        let r = try await host.server.callTool("reverse_analyze", [
            "targetPath": .string(sample.path("artifact.bin")),
            "task": .string("show me how to bypass drm on this app"),
        ])
        #expect(r.isToolError && r.resultText.contains("Reverse cannot help with that request"))
        #expect(r.resultText.contains("REA DISCLAIMER.md"))
    }

    @Test func reverseAnalyzeRejectsOutsideScope() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let system = try await host.server.callTool("reverse_analyze",
                                                    ["targetPath": .string("/etc/passwd")])
        #expect(system.isToolError && system.resultText.contains("blocked system directory"))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let elsewhere = try await host.server.callTool("reverse_analyze",
                                                       ["targetPath": .string((home as NSString).appendingPathComponent("Pictures/artifact"))])
        #expect(elsewhere.isToolError && elsewhere.resultText.contains("outside the Reverse scope"))
    }

    @Test func reverseAnalyzeRejectsDirectory() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("reverse_analyze", ["targetPath": .string(sample.url.path)])
        #expect(r.isToolError && r.resultText.contains("is a directory, not a file"))
    }

    @Test func reverseAnalyzeHonestlyFailsForValidTarget() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "artifact.bin", "fake binary")
        let r = try await host.server.callTool("reverse_analyze", [
            "targetPath": .string(sample.path("artifact.bin")),
            "operation": .string("inspect_artifact"),
            "task": .string("What kind of artifact is this?"),
        ])
        #expect(r.isToolError)
        #expect(r.resultText.contains("rea-agents@6.5.0"), "\(r.resultText)")
        #expect(r.resultText.contains("Node.js"), "\(r.resultText)")
        #expect(r.resultText.contains("no binary was analyzed"), "\(r.resultText)")
        #expect(sample.read("artifact.bin") == "fake binary")
    }

    @Test func reverseAnalyzeRejectsBadObjdumpOperation() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "artifact.bin", "fake binary")
        let r = try await host.server.callTool("reverse_analyze", [
            "targetPath": .string(sample.path("artifact.bin")),
            "operation": .string("inspect_with_objdump"),
            "objdumpOperation": .string("bogus"),
        ])
        #expect(r.isToolError && r.resultText.contains("Invalid objdumpOperation 'bogus'"))
    }

    @Test func reverseTimeoutClamps() {
        #expect(EnginesReverseValidator.clampTimeout(nil) == 300)
        #expect(EnginesReverseValidator.clampTimeout(.int(5)) == 10)
        #expect(EnginesReverseValidator.clampTimeout(.int(5000)) == 1800)
        #expect(EnginesReverseValidator.clampTimeout(.double(42.5)) == 42.5)
    }

    @Test func readOnlyPolicyRefusesEngineWrites() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .readOnly)
        try writeFixture(sample, "Sources/Greeter/Target.txt", "hello\n")
        let mutated = try await host.server.callTool("code_mutation_engine", [
            "path": .string("Sources/Greeter/Target.txt"),
            "target": .string("hello"),
            "replacement": .string("bye"),
        ])
        #expect(mutated.isToolError && mutated.resultText.contains("read-only"))
        #expect(sample.read("Sources/Greeter/Target.txt") == "hello\n")
        let patched = try await host.server.callTool("patch_application_engine", [
            "path": .string("Sources/Greeter/Target.txt"),
            "original": .string("hello"),
            "updated": .string("bye"),
        ])
        #expect(patched.isToolError && patched.resultText.contains("read-only"))
        #expect(sample.read("Sources/Greeter/Target.txt") == "hello\n")
        let resolved = try await host.server.callTool("dependency_resolution_engine",
                                                      ["packageURL": .string("https://example.com/foo.git")])
        #expect(resolved.isToolError && resolved.resultText.contains("read-only"))
    }
}
