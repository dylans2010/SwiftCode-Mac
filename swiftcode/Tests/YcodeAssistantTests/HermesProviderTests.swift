import Foundation
import Testing
@testable import YcodeAssistant

struct HermesProviderTests {

    func collectHermes(_ s: AsyncThrowingStream<ChatEvent, Error>) async throws -> (text: String, events: [ChatEvent]) {
        var text = ""
        var events: [ChatEvent] = []
        for try await e in s {
            events.append(e)
            if case .text(let t) = e { text += t }
        }
        return (text, events)
    }

    final class HermesTestDir {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-hermes-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    func fakeHermesScript(in dir: URL, exitStatus: Int = 0, stderr: String = "", emitResult: Bool = true) throws -> URL {
        let url = dir.appendingPathComponent("hermes")
        let resultLine = emitResult
            ? "            printf '%s\\n' '{\"type\":\"result\",\"session_id\":\"sess-1\",\"exit_code\":0,\"text\":\"hello key-present\",\"tokens\":{\"input\":3,\"output\":4}}'\n"
            : ""
        let script = """
            #!/bin/sh
            echo "$*" > "$PWD/argv.txt"
            if [ -n "$OPENROUTER_API_KEY" ]; then M=key-present; else M=key-absent; fi
            printf '%s\\n' '{"type":"system","model":"test-model","session_id":"sess-1"}'
            printf '{"type":"text","text":"hello %s"}\\n' "$M"
            printf '%s\\n' '{"type":"tool_use","name":"read_file","input":{"path":"README.md"}}'
            printf '%s\\n' '{"type":"tool_result","name":"read_file","output":"contents","duration_ms":12,"is_error":false}'
            \(resultLine)\(stderr.isEmpty ? "" : "printf '%s\\n' '\(stderr)' >&2\n")
            exit \(exitStatus)
            """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static let fakeKey = "fake-test-key"

    @Test func modelIDParsing() {
        #expect(HermesModelID.parse("hermes:openrouter:anthropic/claude-sonnet-4-6")?.spec == "openrouter:anthropic/claude-sonnet-4-6")
        #expect(HermesModelID.parse("hermes:gpt-5.5")?.spec == "gpt-5.5")
        #expect(HermesModelID.parse("openrouter:anthropic/claude-sonnet-4-6") == nil)
        #expect(HermesModelID.parse("opencode:anthropic/claude-sonnet-4-5") == nil)
        #expect(HermesModelID.parse("anthropic/claude-sonnet-4-5") == nil)
        #expect(HermesModelID.parse("hermes:") == nil)
        #expect(HermesModelID.parse("hermes:openrouter:") == nil)
        #expect(HermesModelID.parse("") == nil)
    }

    @Test func modelProviderSplit() {
        let withProvider = HermesModelID.parse("hermes:openrouter:anthropic/claude-sonnet-4-6")
        #expect(withProvider?.provider == "openrouter")
        #expect(withProvider?.model == "anthropic/claude-sonnet-4-6")
        let bare = HermesModelID.parse("hermes:gpt-5.5")
        #expect(bare?.provider == nil)
        #expect(bare?.model == "gpt-5.5")
    }

    @Test func argumentConstruction() {
        var config = HermesConfiguration()
        config.toolsets = "file,web"
        config.maxTurns = 25
        let args = HermesProvider.buildArguments(
            model: HermesModelID.parse("hermes:openrouter:anthropic/claude-sonnet-4-6"),
            directory: "/tmp/workspace", queryFilePath: "/tmp/q.txt", configuration: config)
        #expect(args == [
            "--in", "/tmp/workspace",
            "chat", "--oneshot", "--query-file", "/tmp/q.txt",
            "--format", "stream-json", "--source", "tool",
            "--provider", "openrouter", "--model", "anthropic/claude-sonnet-4-6",
            "--toolsets", "file,web", "--max-turns", "25",
        ])
        #expect(!args.contains("--yolo") && !args.contains("--api-key") && !args.contains("--base-url"))
        #expect(!args.contains("Be helpful.") && !args.contains("Summarize README.md"))
    }

    @Test func bareModelArguments() {
        let args = HermesProvider.buildArguments(
            model: HermesModelID.parse("hermes:gpt-5.5"),
            directory: "/tmp/workspace", queryFilePath: "/tmp/q.txt", configuration: HermesConfiguration())
        #expect(args.contains("--model"))
        #expect(args[args.firstIndex(of: "--model")! + 1] == "gpt-5.5")
        #expect(!args.contains("--provider") && !args.contains("--toolsets") && !args.contains("--max-turns"))
    }

    @Test func defaultModelPassesNoModelFlags() {
        let args = HermesProvider.buildArguments(
            model: nil, directory: "/tmp/workspace", queryFilePath: "/tmp/q.txt", configuration: HermesConfiguration())
        #expect(!args.contains("--provider") && !args.contains("--model"))
    }

    @Test func streamEventParsing() {
        #expect(HermesStreamParser.parseLine(#"{"type":"system","model":"anthropic/claude-sonnet-4-6","session_id":"abc"}"#)
            == .system(sessionId: "abc", model: "anthropic/claude-sonnet-4-6"))
        #expect(HermesStreamParser.parseLine(#"{"type":"text","text":"Hello"}"#) == .text("Hello"))
        #expect(HermesStreamParser.parseLine(#"{"type":"tool_use","name":"read_file","input":{"path":"README.md"}}"#)
            == .toolUse(name: "read_file", inputJSON: #"{"path":"README.md"}"#))
        #expect(HermesStreamParser.parseLine(#"{"type":"tool_result","name":"read_file","output":"contents","duration_ms":12,"is_error":false}"#)
            == .toolResult(name: "read_file", output: "contents", isError: false, durationMs: 12))
        #expect(HermesStreamParser.parseLine(#"{"type":"tool_result","name":"terminal","output":"denied","is_error":true}"#)
            == .toolResult(name: "terminal", output: "denied", isError: true, durationMs: nil))
        #expect(HermesStreamParser.parseLine(#"{"type":"result","session_id":"abc","exit_code":0,"text":"Done","tokens":{"input":1,"output":2}}"#)
            == .result(HermesStreamResult(sessionId: "abc", exitCode: 0, text: "Done", error: nil,
                                           tokens: TokenUsage(inputTokens: 1, outputTokens: 2))))
    }

    @Test func malformedStreamLinesIgnored() {
        for line in ["", "   ", "not json", #"{"type":"text"}"#, #"{"type":"mystery","x":1}"#, #"{"type":"tool_use","input":{}}"#] {
            #expect(HermesStreamParser.parseLine(line) == .ignored)
        }
    }

    @Test func promptBuilder() {
        #expect(HermesPromptBuilder.build(systemPrompt: "Be helpful.", objective: "Summarize README.md")
            == "Be helpful.\n\n---\n\nSummarize README.md")
        #expect(HermesPromptBuilder.build(systemPrompt: "", objective: "Task") == "Task")
        #expect(HermesPromptBuilder.build(systemPrompt: "Prompt", objective: "") == "Prompt")
    }

    @Test func eventParserMapping() throws {
        var parser = HermesStreamEventParser()
        #expect(try parser.parse(#"{"type":"system","model":"m","session_id":"abc"}"#) == [])
        #expect(try parser.parse(#"{"type":"text","text":"Hello"}"#) == [.text("Hello")])
        #expect(try parser.parse(#"{"type":"tool_use","name":"read_file","input":{"path":"README.md"}}"#)
            == [.activity("read_file: README.md")])
        #expect(try parser.parse(#"{"type":"tool_result","name":"read_file","output":"contents","is_error":false}"#)
            == [.activity("read_file ✓")])
        #expect(try parser.parse(#"{"type":"tool_result","name":"terminal","output":"denied","is_error":true}"#)
            == [.activity("terminal ✗")])
        #expect(try parser.parse(#"{"type":"result","session_id":"abc","exit_code":0,"text":"Done","tokens":{"input":1,"output":2}}"#) == [])
        #expect(parser.finish() == [.finished(TokenUsage(inputTokens: 1, outputTokens: 2))])
        #expect(parser.finish() == [])
    }

    @Test func eventParserUsesResultTextWhenNoDeltaArrived() throws {
        var parser = HermesStreamEventParser()
        #expect(try parser.parse(#"{"type":"result","session_id":"abc","exit_code":0,"text":"Done","tokens":{"input":1,"output":2}}"#)
            == [.text("Done")])
        #expect(parser.finish() == [.finished(TokenUsage(inputTokens: 1, outputTokens: 2))])
    }

    @Test func eventParserThrowsOnFailedResult() {
        var parser = HermesStreamEventParser()
        do {
            _ = try parser.parse(#"{"type":"result","session_id":"abc","exit_code":1,"text":"","error":"provider unavailable"}"#)
            Issue.record("A non-zero Hermes result should have thrown.")
        } catch let e as AssistantError {
            if case .tool(let name, let message) = e {
                #expect(name == "Hermes")
                #expect(message.contains("provider unavailable"))
            } else {
                Issue.record("Wrong AssistantError for a failed result: \(e)")
            }
        } catch {
            Issue.record("Wrong error type for a failed result: \(error)")
        }
    }

    @Test func availabilityNotInstalledWhenBinaryAbsent() async {
        let locator = CLIToolLocator(environment: ["PATH": "/nonexistent-dir"], home: "/nonexistent-home",
                                     isExecutable: { _ in false })
        let provider = HermesProvider(locator: locator)
        let availability = await provider.availability()
        #expect(!availability.isReady)
        if case .notInstalled(let hint) = availability {
            #expect(hint.contains("hermes setup"))
        } else {
            Issue.record("Expected .notInstalled, got \(availability)")
        }
    }

    @Test func availabilityReportsConfiguredModel() async throws {
        let home = try HermesTestDir()
        let hermesHome = home.url.appendingPathComponent(".hermes", isDirectory: true)
        try FileManager.default.createDirectory(at: hermesHome, withIntermediateDirectories: true)
        try """
            # Hermes config
            model:
              provider: openrouter
              default: vendor/model-x
            terminal:
              backend: test
            """.write(to: hermesHome.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        let provider = HermesProvider(executable: URL(fileURLWithPath: "/nonexistent/hermes"), homeDirectory: home.url)
        let availability = await provider.availability()
        #expect(availability == .ready([ModelInfo(id: "hermes:openrouter:vendor/model-x", displayName: "openrouter:vendor/model-x")]))
    }

    @Test func availabilityFallsBackToDefaultModel() async throws {
        let home = try HermesTestDir()
        let provider = HermesProvider(executable: URL(fileURLWithPath: "/nonexistent/hermes"), homeDirectory: home.url)
        let availability = await provider.availability()
        #expect(availability == .ready([ModelInfo(id: "", displayName: "Default")]))
        #expect(await provider.contextWindow(model: "") == nil)
    }

    @Test func configuredModelSpecs() throws {
        let home = try HermesTestDir()
        #expect(HermesProvider.readConfiguredModelSpecs(homeDirectory: home.url) == [])
        let hermesHome = home.url.appendingPathComponent(".hermes", isDirectory: true)
        try FileManager.default.createDirectory(at: hermesHome, withIntermediateDirectories: true)
        try "model:\n  provider: openrouter\n  default: vendor/model-x\n"
            .write(to: hermesHome.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        #expect(HermesProvider.readConfiguredModelSpecs(homeDirectory: home.url) == ["openrouter:vendor/model-x"])
        try "model:\n  provider: openrouter\n"
            .write(to: hermesHome.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        #expect(HermesProvider.readConfiguredModelSpecs(homeDirectory: home.url) == [])
    }

    @Test func modelOutputParsing() {
        #expect(HermesProvider.parseModelOutput("Current model: openrouter:anthropic/claude-sonnet-4-6\nProvider: openrouter")
            == ["openrouter:anthropic/claude-sonnet-4-6"])
        #expect(HermesProvider.parseModelOutput("Model: gpt-5.5") == ["gpt-5.5"])
        #expect(HermesProvider.parseModelOutput("https://example.com/x") == [])
    }

    @Test func credentialMappingOnlyForDocumentedProviders() {
        #expect(HermesProvider.credentialEnvironmentVariable(forProvider: "openrouter") == "OPENROUTER_API_KEY")
        #expect(HermesProvider.credentialEnvironmentVariable(forProvider: "openai-api") == "OPENAI_API_KEY")
        #expect(HermesProvider.credentialEnvironmentVariable(forProvider: "anthropic") == nil)
        #expect(HermesProvider.credentialEnvironmentVariable(forProvider: nil) == nil)
        #expect(HermesProvider.apiKeyAccount(forProvider: "openrouter") == "hermes.openrouter-api-key")
        #expect(HermesProvider.apiKeyAccount(forProvider: "anthropic") == nil)
    }

    @Test func controlledEnvironmentNeverInheritsHermesVariables() {
        let env = HermesProvider.environment(
            executable: URL(fileURLWithPath: "/opt/homebrew/bin/hermes"),
            parent: ["PATH": "/usr/bin:/bin", "HOME": "/home/test", "TMPDIR": "/tmp/",
                     "HERMES_YOLO_MODE": "1", "HERMES_ACCEPT_HOOKS": "1"],
            apiKey: Self.fakeKey, apiKeyVariable: "OPENROUTER_API_KEY")
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin")
        #expect(env["HOME"] == "/home/test")
        #expect(env["TMPDIR"] == "/tmp/")
        #expect(env["HERMES_YOLO_MODE"] == nil && env["HERMES_ACCEPT_HOOKS"] == nil)
        #expect(env["OPENROUTER_API_KEY"] == Self.fakeKey)
        #expect(env.count == 4)
    }

    @Test func redactionRemovesFakeKey() {
        let redacted = HermesProvider.redacted("auth failed for \(Self.fakeKey) at openrouter", secrets: [Self.fakeKey])
        #expect(!redacted.contains(Self.fakeKey))
        #expect(redacted.contains("[redacted]"))
        let explained = HermesProvider.explain(status: 1, stderrTail: "login failed: \(Self.fakeKey)", secrets: [Self.fakeKey])
        #expect(!explained.contains(Self.fakeKey))
        #expect(explained.contains("sign in"))
    }

    @Test func sendRunsStandInAndStreamsEvents() async throws {
        let workspace = try HermesTestDir()
        let script = try fakeHermesScript(in: workspace.url)
        let store = MemorySecretStore()
        try store.write(Data(Self.fakeKey.utf8), for: "hermes.openrouter-api-key")
        let provider = HermesProvider(executable: script, secretStore: store)
        let request = ChatRequest(model: "hermes:openrouter:test-model", instructions: "Be helpful.",
                                  messages: [ChatMessage(.user, "Summarize README.md")],
                                  workingDirectory: workspace.url)
        let (text, events) = try await collectHermes(provider.send(request))
        #expect(text == "hello key-present")
        #expect(!text.contains(Self.fakeKey))
        #expect(events.contains(.activity("read_file: README.md")))
        #expect(events.contains(.activity("read_file ✓")))
        #expect(events.contains(.finished(TokenUsage(inputTokens: 3, outputTokens: 4))))
        for event in events {
            #expect(!String(describing: event).contains(Self.fakeKey))
        }
        let argv = try String(contentsOf: workspace.url.appendingPathComponent("argv.txt"), encoding: .utf8)
        #expect(argv.contains("--in \(workspace.url.path)"))
        #expect(argv.contains("chat --oneshot --query-file"))
        #expect(argv.contains("--format stream-json --source tool"))
        #expect(argv.contains("--provider openrouter --model test-model"))
        #expect(!argv.contains(Self.fakeKey))
        #expect(!argv.contains("--yolo") && !argv.contains("--api-key"))
        #expect(!argv.contains("Be helpful.") && !argv.contains("Summarize README.md"))
        let words = argv.split(separator: " ").map(String.init)
        if let i = words.firstIndex(of: "--query-file") {
            #expect(!FileManager.default.fileExists(atPath: words[i + 1]))
        } else {
            Issue.record("argv had no --query-file: \(argv)")
        }
    }

    @Test func sendWithoutStoredKeyLeavesCredentialAbsent() async throws {
        let workspace = try HermesTestDir()
        let script = try fakeHermesScript(in: workspace.url)
        let provider = HermesProvider(executable: script, secretStore: MemorySecretStore())
        let request = ChatRequest(model: "hermes:openrouter:test-model", instructions: "Be helpful.",
                                  messages: [ChatMessage(.user, "Hi")], workingDirectory: workspace.url)
        let (text, _) = try await collectHermes(provider.send(request))
        #expect(text == "hello key-absent")
    }

    @Test func invalidModelFailsBeforeLaunch() async throws {
        let workspace = try HermesTestDir()
        let script = try fakeHermesScript(in: workspace.url)
        let provider = HermesProvider(executable: script)
        let request = ChatRequest(model: "hermes:openrouter:", instructions: "Be helpful.",
                                  messages: [ChatMessage(.user, "Hi")], workingDirectory: workspace.url)
        do {
            _ = try await collectHermes(provider.send(request))
            Issue.record("An invalid Hermes model id should have failed before launch.")
        } catch let e as AssistantError {
            if case .modelNotFound = e { } else { Issue.record("Wrong error for invalid model id: \(e)") }
        }
        #expect(!FileManager.default.fileExists(atPath: workspace.url.appendingPathComponent("argv.txt").path))
    }

    @Test func failedRunSurfacesStderr() async throws {
        let workspace = try HermesTestDir()
        let script = try fakeHermesScript(in: workspace.url, exitStatus: 1, stderr: "hermes: provider unavailable", emitResult: false)
        let provider = HermesProvider(executable: script)
        let request = ChatRequest(model: nil, instructions: "Be helpful.",
                                  messages: [ChatMessage(.user, "Hi")], workingDirectory: workspace.url)
        do {
            _ = try await collectHermes(provider.send(request))
            Issue.record("A failing Hermes run should have thrown.")
        } catch {
            #expect(String(describing: error).contains("provider unavailable"))
        }
    }
}
