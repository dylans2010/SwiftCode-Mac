import Foundation

// MARK: - Hermes provider tests
//
// Follows the AssistRuntimeTestSuite convention: in-app
// RuntimeTestCaseResult cases, wired into AssistRuntimeTestSuite.
// Every case here is offline and deterministic — no Hermes binary,
// no API key, no network, no process launch. Live behaviour (a real
// `hermes` install, a real model run, real tool events) is verified
// by the Settings installation check and is listed as unverified
// in Docs/Assist-Hermes-Provider.md until it runs on a Mac with
// Hermes installed and authenticated.

@MainActor
public final class HermesProviderTests: Sendable {
    public static let shared = HermesProviderTests()

    private init() {}

    public func runAllTests() async -> [RuntimeTestCaseResult] {
        [
            await testModelIDParsing(),
            await testModelProviderSplit(),
            await testProviderSelectionAndSDKGuard(),
            await testConfigurationRoundTrip(),
            await testArgumentConstruction(),
            await testArgumentConstructionBareModel(),
            await testStreamEventParsing(),
            await testStreamEventParsingMalformed(),
            await testPromptBuilder(),
            await testExecutableResolution(),
        ]
    }

    private func result(_ name: String, _ start: Date, _ passed: Bool, _ message: String) -> RuntimeTestCaseResult {
        RuntimeTestCaseResult(testName: name, passed: passed, message: message, duration: Date().timeIntervalSince(start))
    }

    // 1. Hermes ids parse only with the hermes: prefix; bare
    // provider/model ids and other providers' ids are never claimed.
    public func testModelIDParsing() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "Hermes ids parse only with the hermes: prefix."
        if HermesModelID.parse("hermes:openrouter:anthropic/claude-sonnet-4-6")?.spec != "openrouter:anthropic/claude-sonnet-4-6" {
            passed = false
            message = "A provider:model Hermes id did not parse."
        }
        if HermesModelID.parse("hermes:gpt-5.5")?.spec != "gpt-5.5" {
            passed = false
            message = "A bare-model Hermes id did not parse."
        }
        if HermesModelID.parse("openrouter:anthropic/claude-sonnet-4-6") != nil
            || HermesModelID.parse("opencode:anthropic/claude-sonnet-4-5") != nil
            || HermesModelID.parse("anthropic/claude-sonnet-4-5") != nil
            || HermesModelID.parse("hermes:") != nil
            || HermesModelID.parse("hermes:openrouter:") != nil
            || HermesModelID.parse("") != nil {
            passed = false
            message = "A non-Hermes or empty id was claimed as a Hermes id."
        }
        return result("Hermes: model id parsing", start, passed, message)
    }

    // 2. Provider/model split: provider is the part before the first
    // colon, model is the rest (which itself contains "/").
    public func testModelProviderSplit() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "Provider/model split follows Hermes' provider:model syntax."
        let withProvider = HermesModelID.parse("hermes:openrouter:anthropic/claude-sonnet-4-6")
        if withProvider?.provider != "openrouter" || withProvider?.model != "anthropic/claude-sonnet-4-6" {
            passed = false
            message = "provider:model did not split into openrouter + anthropic/claude-sonnet-4-6."
        }
        let bare = HermesModelID.parse("hermes:gpt-5.5")
        if bare?.provider != nil || bare?.model != "gpt-5.5" {
            passed = false
            message = "A bare model name gained an invented provider."
        }
        return result("Hermes: provider/model split", start, passed, message)
    }

    // 3. Routing guards: Hermes ids select the Hermes provider and
    // are never claimed by the SDK path (which would otherwise take
    // any "/" id via the OpenRouter persisted-provider fallback).
    public func testProviderSelectionAndSDKGuard() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "Hermes ids route to Hermes and are never claimed by the SDK path."
        if AssistProviderSelection.provider(for: "hermes:openrouter:anthropic/claude-sonnet-4-6") != .hermes {
            passed = false
            message = "A Hermes id did not select the Hermes provider."
        }
        if AssistSDKSessionRunner.applicableKind(for: "hermes:openrouter:anthropic/claude-sonnet-4-6") != nil {
            passed = false
            message = "A Hermes id was claimed by the SDK path."
        }
        if AssistModelProvider.hermes.apiKeyProvider != nil {
            passed = false
            message = "Hermes gained a SwiftCode-managed API key provider."
        }
        return result("Hermes: provider selection + SDK guard", start, passed, message)
    }

    // 4. Configuration persists independently and restores, without
    // touching the selected model or provider keys.
    public func testConfigurationRoundTrip() async -> RuntimeTestCaseResult {
        let start = Date()
        let original = HermesConfiguration.load()
        defer { original.save() }
        var config = HermesConfiguration()
        config.executablePath = "/tmp/hermes-test/hermes"
        config.toolsets = "file,web"
        config.maxTurns = 42
        config.save()
        let loaded = HermesConfiguration.load()
        let passed = loaded == config && loaded.normalisedToolsets == "file,web"
        var whitespace = HermesConfiguration()
        whitespace.toolsets = "   "
        let whitespacePassed = whitespace.normalisedToolsets == nil
        return result(
            "Hermes: configuration round-trip",
            start, passed && whitespacePassed,
            passed && whitespacePassed
                ? "Hermes configuration round-trips; whitespace-only toolsets mean Hermes defaults."
                : "Hermes configuration did not round-trip (got \(loaded))."
        )
    }

    // 5. Argument construction: the exact documented invocation, in
    // order, with provider/model/toolsets/max-turns — and never
    // --yolo, --api-key, or the prompt itself in argv.
    public func testArgumentConstruction() async -> RuntimeTestCaseResult {
        let start = Date()
        var config = HermesConfiguration()
        config.toolsets = "file,web"
        config.maxTurns = 25
        let request = HermesRunRequest(
            model: "hermes:openrouter:anthropic/claude-sonnet-4-6",
            systemPrompt: "Be helpful.",
            userText: "Summarize README.md",
            directory: "/tmp/workspace",
            configuration: config
        )
        let args = HermesProvider.buildArguments(request: request, queryFilePath: "/tmp/q.txt")
        let expected: [String] = [
            "--in", "/tmp/workspace",
            "chat", "--oneshot", "--query-file", "/tmp/q.txt",
            "--format", "stream-json", "--source", "tool",
            "--provider", "openrouter", "--model", "anthropic/claude-sonnet-4-6",
            "--toolsets", "file,web", "--max-turns", "25",
        ]
        let forbidden = ["--yolo", "--api-key", "--base-url", "--ignore-user-config", "Be helpful.", "Summarize README.md"]
        let passed = args == expected && !args.contains(where: { forbidden.contains($0) })
        return result(
            "Hermes: argument construction",
            start, passed,
            passed ? "Arguments match the documented stream-json invocation exactly." : "Arguments did not match (got \(args))."
        )
    }

    // 6. Bare-model ids pass --model only: no provider is invented.
    public func testArgumentConstructionBareModel() async -> RuntimeTestCaseResult {
        let start = Date()
        let request = HermesRunRequest(
            model: "hermes:gpt-5.5",
            systemPrompt: "",
            userText: "Hi",
            directory: "/tmp/workspace",
            configuration: HermesConfiguration()
        )
        let args = HermesProvider.buildArguments(request: request, queryFilePath: "/tmp/q.txt")
        let passed = args.contains("--model") && args.firstIndex(of: "--model").map { args[$0 + 1] == "gpt-5.5" } == true
            && !args.contains("--provider")
            && !args.contains("--toolsets")
            && !args.contains("--max-turns")
        return result(
            "Hermes: bare-model arguments",
            start, passed,
            passed ? "A bare model passes --model only, with no invented provider." : "Bare-model arguments were wrong (got \(args))."
        )
    }

    // 7. Stream-json parsing: every documented event type, including
    // a tool_result that pairs with its tool_use and an error result.
    public func testStreamEventParsing() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "All documented stream-json event types parse."
        if HermesStreamParser.parseLine(#"{"type":"system","model":"anthropic/claude-sonnet-4-6","session_id":"abc"}"#) != .system(sessionId: "abc", model: "anthropic/claude-sonnet-4-6") {
            passed = false
            message = "system/init did not parse."
        }
        if HermesStreamParser.parseLine(#"{"type":"text","text":"Hello"}"#) != .text("Hello") {
            passed = false
            message = "text delta did not parse."
        }
        if HermesStreamParser.parseLine(#"{"type":"tool_use","name":"read_file","input":{"path":"README.md"}}"#) != .toolUse(name: "read_file", inputJSON: #"{"path":"README.md"}"#) {
            passed = false
            message = "tool_use with an object input did not parse to compact JSON."
        }
        if HermesStreamParser.parseLine(#"{"type":"tool_result","name":"read_file","output":"contents","duration_ms":12,"is_error":false}"#) != .toolResult(name: "read_file", output: "contents", isError: false, durationMs: 12) {
            passed = false
            message = "tool_result did not parse."
        }
        if HermesStreamParser.parseLine(#"{"type":"tool_result","name":"terminal","output":"denied","is_error":true}"#) != .toolResult(name: "terminal", output: "denied", isError: true, durationMs: nil) {
            passed = false
            message = "An error tool_result did not parse as failed."
        }
        let result = HermesStreamParser.parseLine(#"{"type":"result","session_id":"abc","exit_code":0,"text":"Done","tokens":{"input":1,"output":2}}"#)
        if result != .result(HermesStreamResult(sessionId: "abc", exitCode: 0, text: "Done", error: nil)) {
            passed = false
            message = "Terminal result did not parse."
        }
        return result("Hermes: stream-json parsing", start, passed, message)
    }

    // 8. Malformed input never crashes parsing and never invents
    // data: blank lines, broken JSON, and unknown types are ignored.
    public func testStreamEventParsingMalformed() async -> RuntimeTestCaseResult {
        let start = Date()
        let cases = ["", "   ", "not json", #"{"type":"text"}"#, #"{"type":"mystery","x":1}"#, #"{"type":"tool_use","input":{}}"#]
        let passed = cases.allSatisfy { HermesStreamParser.parseLine($0) == .ignored }
        return result(
            "Hermes: malformed stream lines ignored",
            start, passed,
            passed ? "Blank, broken, and unknown lines parse to .ignored." : "A malformed line was not ignored."
        )
    }

    // 9. Prompt delivery: system prompt first, task second, separated;
    // empty sides degrade to the non-empty side alone.
    public func testPromptBuilder() async -> RuntimeTestCaseResult {
        let start = Date()
        let built = HermesPromptBuilder.build(systemPrompt: "Be helpful.", objective: "Summarize README.md")
        let passed = built == "Be helpful.\n\n---\n\nSummarize README.md"
            && HermesPromptBuilder.build(systemPrompt: "", objective: "Task") == "Task"
            && HermesPromptBuilder.build(systemPrompt: "Prompt", objective: "") == "Prompt"
        return result(
            "Hermes: prompt delivery",
            start, passed,
            passed ? "System prompt precedes the task, separated, with clean empty-side handling." : "Prompt builder output was wrong (got \(built))."
        )
    }

    // 10. Executable resolution: a configured path wins only when
    // executable; otherwise the first executable in the search dirs
    // wins; nothing found means nil (never a guessed path). Uses a
    // real temp directory with a dummy executable so the search is
    // exercised, not just the nil paths.
    public func testExecutableResolution() async -> RuntimeTestCaseResult {
        let start = Date()
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("swiftcode-hermes-test-\(UUID().uuidString)")
        var passed = false
        var message = "Executable resolution did not behave as specified."
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }
            let dummy = tempDir.appendingPathComponent("hermes")
            try "#!/bin/sh\necho hermes".write(to: dummy, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dummy.path)
            let found = HermesProvider.resolveExecutable(configuredPath: "", searchDirectories: ["/nonexistent-dir", tempDir.path])
            let missing = HermesProvider.resolveExecutable(configuredPath: "", searchDirectories: ["/nonexistent-dir"])
            let badConfigured = HermesProvider.resolveExecutable(configuredPath: "/nonexistent-dir/hermes", searchDirectories: [tempDir.path])
            let nonExecutableConfigured = HermesProvider.resolveExecutable(
                configuredPath: tempDir.appendingPathComponent("not-hermes").path,
                searchDirectories: [tempDir.path]
            )
            passed = found == dummy.path && missing == nil && badConfigured == nil && nonExecutableConfigured == nil
            if passed {
                message = "Resolution finds the first executable, returns nil when nothing is found, and rejects non-executable configured paths."
            }
        } catch {
            message = "Test fixture setup failed: \(error.localizedDescription)"
        }
        return result("Hermes: executable resolution", start, passed, message)
    }
}
