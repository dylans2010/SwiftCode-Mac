import Foundation
import os

@MainActor
public final class AssistProviderTests: Sendable {
    public static let shared = AssistProviderTests()

    private init() {}

    public func runAllTests() async -> [RuntimeTestCaseResult] {
        [
            await testOpenCodeModelIDParsing(),
            await testOpenCodeSpecificationIsNotMisrouted(),
            await testOpenCodeProviderCatalogParsing(),
            await testOpenCodeEventParsing(),
            await testOpenCodeConfigurationRoundTrip(),
            await testOpenCodeProviderHasNoStoredKeyAndFailsClosed(),
            await testPersistedProviderRoundTrip(),
            await testOpenRouterValidationRejectsNonSlashIDOffline(),
        ]
    }

    private func result(_ name: String, _ start: Date, _ passed: Bool, _ message: String) -> RuntimeTestCaseResult {
        RuntimeTestCaseResult(testName: name, passed: passed, message: message, duration: Date().timeIntervalSince(start))
    }

    public func testOpenCodeModelIDParsing() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "OpenCode model ids parse and round-trip; bare provider/model ids are not claimed."

        let parsed = OpenCodeModelID.parse("opencode:anthropic/claude-sonnet-4-5")
        if parsed?.providerID != "anthropic" || parsed?.modelID != "claude-sonnet-4-5" {
            passed = false
            message = "Failed to parse opencode:anthropic/claude-sonnet-4-5."
        }
        let nested = OpenCodeModelID.parse("opencode:openrouter/moonshotai/kimi-k2")
        if nested?.providerID != "openrouter" || nested?.modelID != "moonshotai/kimi-k2" {
            passed = false
            message = "Failed to keep nested model segments in the model id."
        }
        if OpenCodeModelID.parse("anthropic/claude-sonnet-4-5") != nil {
            passed = false
            message = "A bare OpenRouter id was misparsed as an OpenCode id (would misroute it)."
        }
        if OpenCodeModelID.parse("opencode:") != nil || OpenCodeModelID.parse("opencode:/x") != nil || OpenCodeModelID.parse("opencode:a/") != nil {
            passed = false
            message = "Malformed opencode: ids were accepted."
        }
        if parsed?.storedID != "opencode:anthropic/claude-sonnet-4-5" {
            passed = false
            message = "Parsed id did not round-trip to its stored form."
        }
        return result("Assist Providers: OpenCode model id parsing", start, passed, message)
    }

    public func testOpenCodeSpecificationIsNotMisrouted() async -> RuntimeTestCaseResult {
        let start = Date()
        let spec = AgentModelAdapter.shared.specification(for: "opencode:anthropic/claude-sonnet-4-5")
        let passed = spec.provider == .openCode && spec.id == "opencode:anthropic/claude-sonnet-4-5"
        return result(
            "Assist Providers: OpenCode specification routing",
            start,
            passed,
            passed
                ? "opencode:anthropic/claude-… resolves to provider OpenCode, not Anthropic."
                : "opencode:anthropic/claude-… resolved to \(spec.provider.rawValue); it would be misrouted."
        )
    }

    public func testOpenCodeProviderCatalogParsing() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "Provider catalog parses array and provider-keyed shapes, dedupes, and skips id-less entries."

        let arrayJSON = """
        {"providers": [
          {"id": "anthropic", "models": [{"id": "claude-sonnet-4-5"}, {"modelID": "claude-haiku-4-5"}]},
          {"id": "anthropic", "models": [{"id": "claude-sonnet-4-5"}]},
          {"id": "openai", "models": [{"name": "no-id"}]}
        ]}
        """
        let keyedJSON = """
        {"anthropic": {"models": {"claude-sonnet-4-5": {}}}}
        """
        let arrayModels = OpenCodeProviderCatalog.parseModels(from: Data(arrayJSON.utf8))
        if arrayModels.map(\.storedID) != ["opencode:anthropic/claude-haiku-4-5", "opencode:anthropic/claude-sonnet-4-5"] {
            passed = false
            message = "Array catalog parsed as \(arrayModels.map(\.storedID)); expected deduped, sorted OpenCode ids."
        }
        let keyedModels = OpenCodeProviderCatalog.parseModels(from: Data(keyedJSON.utf8))
        if keyedModels.map(\.storedID) != ["opencode:anthropic/claude-sonnet-4-5"] {
            passed = false
            message = "Provider-keyed catalog parsed as \(keyedModels.map(\.storedID))."
        }
        if !OpenCodeProviderCatalog.parseModels(from: Data("not json".utf8)).isEmpty {
            passed = false
            message = "Unparseable catalog data produced fabricated models."
        }
        return result("Assist Providers: OpenCode catalog parsing", start, passed, message)
    }

    public func testOpenCodeEventParsing() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "Event stream parsing yields text deltas, flags tool parts, and reports idle."

        let delta = OpenCodeEvent.parse(line: #"data: {"type":"message.part.delta","properties":{"sessionID":"s1","part":{"type":"text","text":"hello"}}}"#)
        if case .parsed(let sessionID, let kind) = delta {
            if sessionID != "s1" { passed = false; message = "Delta session id was not captured." }
            if case .textDelta(let text) = kind {
                if text != "hello" { passed = false; message = "Delta text was not captured." }
            } else {
                passed = false; message = "Text delta was not classified as a text delta."
            }
        } else {
            passed = false; message = "Text delta line did not parse."
        }

        let tool = OpenCodeEvent.parse(line: #"data: {"type":"message.part.delta","properties":{"sessionID":"s1","part":{"type":"tool","tool":"read"}}}"#)
        if case .parsed(_, let kind) = tool, case .tool = kind {
        } else {
            passed = false; message = "Tool part was not classified as a tool event (fail-closed gate would miss it)."
        }

        let idle = OpenCodeEvent.parse(line: #"data: {"type":"session.idle","properties":{"sessionID":"s1"}}"#)
        if case .parsed(_, let kind) = idle, case .idle = kind {
        } else {
            passed = false; message = "session.idle was not classified as idle."
        }

        if OpenCodeEvent.parse(line: "not a data line") != nil {
            passed = false; message = "A non-SSE line parsed as an event."
        }
        return result("Assist Providers: OpenCode event parsing", start, passed, message)
    }

    public func testOpenCodeConfigurationRoundTrip() async -> RuntimeTestCaseResult {
        let start = Date()
        let original = OpenCodeConfiguration.load()
        defer {
            original.save()
        }
        var config = OpenCodeConfiguration()
        config.serverURL = URL(string: "http://127.0.0.1:5999")!
        config.agentName = "swiftcode-test"
        config.managedServerEnabled = true
        config.save()
        let loaded = OpenCodeConfiguration.load()
        let passed = loaded.serverURL.absoluteString == "http://127.0.0.1:5999"
            && loaded.agentName == "swiftcode-test"
            && loaded.managedServerEnabled == true
            && loaded.isLoopback
        return result(
            "Assist Providers: OpenCode configuration persistence",
            start,
            passed,
            passed ? "OpenCode settings round-trip through UserDefaults, including loopback detection." : "Configuration did not round-trip: \(loaded)"
        )
    }

    public func testOpenCodeProviderHasNoStoredKeyAndFailsClosed() async -> RuntimeTestCaseResult {
        let start = Date()
        let provider = AssistModelProvider.openCode
        var passed = provider.apiKeyProvider == nil
        var message = "OpenCode exposes no stored-key provider."
        if provider.endpoint != OpenCodeConfiguration.load().serverURL {
            passed = false
            message = "OpenCode endpoint is not the configured server URL."
        }
        let response = await AssistLLMService.generateResponse(prompt: "hi", provider: .openCode, apiKey: nil, modelOverride: "opencode:anthropic/claude-sonnet-4-5")
        if response.success {
            passed = false
            message = "Legacy LLM path succeeded for OpenCode instead of failing closed — it could silently route to another provider."
        }
        let stored = await provider.storedAPIKey()
        if stored != nil {
            passed = false
            message = "storedAPIKey() returned a key for OpenCode."
        }
        return result("Assist Providers: OpenCode key isolation + fail-closed routing", start, passed, message)
    }

    public func testPersistedProviderRoundTrip() async -> RuntimeTestCaseResult {
        let start = Date()
        let original = AssistProviderSelection.persistedProvider
        defer {
            AssistProviderSelection.persistedProvider = original
        }
        AssistProviderSelection.persistedProvider = .openCode
        let passed = AssistProviderSelection.persistedProvider == .openCode
            && AssistModelProvider(rawValue: "OpenCode") == .openCode
        return result(
            "Assist Providers: persisted provider selection",
            start,
            passed,
            passed ? "assist.selectedProvider round-trips OpenCode." : "Persisted provider did not round-trip OpenCode."
        )
    }

    public func testOpenRouterValidationRejectsNonSlashIDOffline() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = false
        var message = "validateModel rejected a bare model id without network access."
        do {
            _ = try await OpenRouterAssistProvider.validateModel("gpt-4o")
            message = "validateModel accepted a bare model id that is not an OpenRouter identifier."
        } catch let error as OpenRouterAssistError {
            if case .notAnOpenRouterModel = error {
                passed = true
            } else {
                message = "validateModel threw \(error) instead of notAnOpenRouterModel."
            }
        } catch {
            message = "validateModel threw an unexpected error: \(error.localizedDescription)"
        }
        return result("Assist Providers: OpenRouter id validation (offline)", start, passed, message)
    }
}
