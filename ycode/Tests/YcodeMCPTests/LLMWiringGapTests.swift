import Foundation
import Testing
import YcodeAssistant
import YcodeIDECore
@testable import YcodeMCP

/// The gap-closure LLM wiring through `tools/call` on a Greeter workspace
/// copy, with the host test seam set to a stub provider: no live network,
/// no real credentials. The `code_refactor` / `intel_autofix` tests are
/// `.disabled` — they can only pass once the coordinator applies the
/// patches for `YcodeTools+FileWriting.swift` / `YcodeTools+Planning.swift`
/// (see `specs/ide/gap-closure-llm.md` §3.3/§3.4); enable them then.
@MainActor
@Suite(.serialized) struct LLMWiringGapTests {
    /// A stub provider that answers with canned text.
    struct StubLLMProvider: AssistantProvider {
        var kind: ProviderKind = .openRouter
        var text: String
        func availability() async -> ProviderAvailability {
            .ready([ModelInfo(id: "stub/model", displayName: "Stub")])
        }
        func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
            let text = text
            return AsyncThrowingStream { continuation in
                continuation.yield(.text(text))
                continuation.yield(.finished(nil))
                continuation.finish()
            }
        }
    }

    /// A service backed by the stub provider, configured as the host
    /// would configure OpenRouter with a stored model.
    func stubService(text: String) -> LLMToolCompletionService {
        var settings = AssistantSettings()
        settings.provider = .openRouter
        settings.setModel("stub/model", for: .openRouter)
        return LLMToolCompletionService(
            backends: AssistantBackends(settings: settings, store: MemorySecretStore(), account: nil),
            providerOverrides: [.openRouter: StubLLMProvider(text: text)])
    }

    /// A service with a configured provider but no credentials and no
    /// overrides: every tool must fail honestly through it.
    func unconfiguredService() -> LLMToolCompletionService {
        var settings = AssistantSettings()
        settings.provider = .openRouter
        return LLMToolCompletionService(
            backends: AssistantBackends(settings: settings, store: MemorySecretStore(), account: nil))
    }

    /// Opens a copy of Greeter with the ported Agentic code + review/docs
    /// tools installed (same filter-first shape as Wave 8's `opened`).
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.agenticCodeTools.map(\.name) + host.reviewDocsTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticCodeTools + host.reviewDocsTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func agenticToolsReturnStubText() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        YcodeMCPHost.llmToolTestService = stubService(text: "func stub() {}\n")
        defer { YcodeMCPHost.llmToolTestService = nil }
        let host = try await opened(sample)
        let cases: [(String, [String: AnyJSON])] = [
            ("generate_code", ["prompt": .string("a greeter struct")]),
            ("refactor_code", ["code": .string("func f() {}"), "instructions": .string("extract a method")]),
            ("review_code", ["code": .string("func f() {}")]),
            ("fix_bugs", ["code": .string("func f() {}"), "issue": .string("it crashes")]),
            ("generate_unit_tests", ["code": .string("struct Greeter {}")]),
            ("generate_integration_tests", ["code": .string("struct Greeter {}")]),
            ("generate_documentation", ["code": .string("struct Greeter {}")]),
            ("generate_comments", ["code": .string("struct Greeter {}")]),
        ]
        for (name, args) in cases {
            let r = try await host.server.callTool(name, args)
            #expect(!r.isToolError, "\(name): \(r.firstText)")
            #expect(r.firstText.contains("func stub() {}"), "\(name): \(r.firstText)")
        }
    }

    @Test func agenticToolsStripFences() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        YcodeMCPHost.llmToolTestService = stubService(text: "```swift\nfunc stub() {}\n```\n")
        defer { YcodeMCPHost.llmToolTestService = nil }
        let host = try await opened(sample)
        let r = try await host.server.callTool("generate_code", ["prompt": .string("a greeter struct")])
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.firstText == "func stub() {}", "\(r.firstText)")
    }

    @Test func codeReviewReturnsStubVerdict() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let verdict = """
            {"status": "task_ready", "summary": "Looks good.", "strengths": ["Clean separation"], \
            "issues": [], "recommendedFixes": [], "user_see": "Passed review.", "confidence": 0.95}
            """
        YcodeMCPHost.llmToolTestService = stubService(text: verdict)
        defer { YcodeMCPHost.llmToolTestService = nil }
        let host = try await opened(sample)
        let r = try await host.server.callTool("code_review", [:])
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.firstText.contains("Review completed via OpenRouter"))
        #expect(r.firstText.contains("Status: task_ready"))
        #expect(r.firstText.contains("Summary: Looks good."))
        #expect(r.firstText.contains("Passed review."))
    }

    @Test func codeReviewRejectsNonJSON() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        YcodeMCPHost.llmToolTestService = stubService(text: "not json at all")
        defer { YcodeMCPHost.llmToolTestService = nil }
        let host = try await opened(sample)
        let r = try await host.server.callTool("code_review", [:])
        #expect(r.isToolError)
        #expect(r.firstText.contains("did not return a JSON verdict"))
    }

    @Test func codeReviewRejectsInvalidStatus() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let verdict = """
            {"status": "maybe", "summary": "Unsure.", "strengths": [], \
            "issues": [], "recommendedFixes": [], "user_see": "", "confidence": 0.5}
            """
        YcodeMCPHost.llmToolTestService = stubService(text: verdict)
        defer { YcodeMCPHost.llmToolTestService = nil }
        let host = try await opened(sample)
        let r = try await host.server.callTool("code_review", [:])
        #expect(r.isToolError)
        #expect(r.firstText.contains("invalid verdict status 'maybe'"))
        #expect(r.firstText.contains("task_ready"))
    }

    @Test func unconfiguredToolsFailHonestly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        YcodeMCPHost.llmToolTestService = unconfiguredService()
        defer { YcodeMCPHost.llmToolTestService = nil }
        let host = try await opened(sample)
        let cases: [(String, [String: AnyJSON])] = [
            ("generate_code", ["prompt": .string("a greeter struct")]),
            ("refactor_code", ["code": .string("func f() {}"), "instructions": .string("extract a method")]),
            ("review_code", ["code": .string("func f() {}")]),
            ("fix_bugs", ["code": .string("func f() {}"), "issue": .string("it crashes")]),
            ("generate_unit_tests", ["code": .string("struct Greeter {}")]),
            ("generate_integration_tests", ["code": .string("struct Greeter {}")]),
            ("generate_documentation", ["code": .string("struct Greeter {}")]),
            ("generate_comments", ["code": .string("struct Greeter {}")]),
        ]
        for (name, args) in cases {
            let r = try await host.server.callTool(name, args)
            #expect(r.isToolError, "\(name) must fail honestly, not fake output")
            #expect(r.firstText.contains("unavailable"), "\(name) message: \(r.firstText)")
            #expect(r.firstText.contains("LLM"), "\(name) message must name the LLM prerequisite: \(r.firstText)")
            #expect(r.firstText.contains("OpenRouter"), "\(name) message must name the provider: \(r.firstText)")
            #expect(r.structured == nil, "\(name) must return no structured content")
        }
        let review = try await host.server.callTool("code_review", [:])
        #expect(review.isToolError)
        #expect(review.firstText.contains("no LLM provider"))
        #expect(review.firstText.contains("task_ready"))
    }

    @Test(.disabled("Needs the coordinator-applied code_refactor patch in YcodeTools+FileWriting.swift (spec §3.3)."))
    func codeRefactorAppliesStubRefactoring() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let refactored = "public struct Greeter {\n    public let salutation: String\n}\n"
        YcodeMCPHost.llmToolTestService = stubService(text: refactored)
        defer { YcodeMCPHost.llmToolTestService = nil }
        let host = try await opened(sample, policy: .allow)
        let before = sample.read("Sources/Greeter/Greeter.swift")
        #expect(before != refactored)
        let r = try await host.server.callTool("code_refactor", [
            "path": .string("Sources/Greeter/Greeter.swift"),
            "action": .string("extract the salutation into its own property"),
        ])
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.firstText.contains("Refactoring 'extract the salutation into its own property' applied to Sources/Greeter/Greeter.swift"))
        #expect(sample.read("Sources/Greeter/Greeter.swift") == refactored)
    }

    @Test(.disabled("Needs the coordinator-applied intel_autofix patch in YcodeTools+Planning.swift (spec §3.4)."))
    func intelAutofixReportsNoIssues() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        // The Greeter fixture is lint-clean (no tabs, no trailing
        // whitespace, no >140-char lines), so no LLM call is made.
        YcodeMCPHost.llmToolTestService = stubService(text: "must not be used")
        defer { YcodeMCPHost.llmToolTestService = nil }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("intel_autofix", ["path": .string(".")])
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.firstText.contains("No lint issues to fix in ."))
    }

    @Test(.disabled("Needs the coordinator-applied intel_autofix patch in YcodeTools+Planning.swift (spec §3.4)."))
    func intelAutofixFixesTrailingWhitespace() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "Sources/Greeter/Linty.swift", "struct Linty {   \n    let x = 1\n}\n")
        let fixed = "struct Linty {\n    let x = 1\n}\n"
        YcodeMCPHost.llmToolTestService = stubService(text: fixed)
        defer { YcodeMCPHost.llmToolTestService = nil }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("intel_autofix", ["path": .string("Sources/Greeter/Linty.swift")])
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.firstText.contains("Auto-fix applied"))
        #expect(sample.read("Sources/Greeter/Linty.swift") == fixed)
    }
}
